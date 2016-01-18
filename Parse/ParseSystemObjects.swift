//
//  ParseSystemObjects.swift
//  Parse
//
//  Created by Rex Sheng on 3/9/15.
//  Copyright (c) 2015 Rex Sheng. All rights reserved.
//

//public protocol 
public struct User: ParseObject {
	public static let className = "_User"
	public var json: Data!
	public init() {}
	public let username = Field<String>("username")
	public let email = Field<String>("email")
}

public struct Installation: ParseObject {
	public static let className = "_Installation"
	public var json: Data!
	public init() {}
}

public struct File: ParseObject {
	public static let className = ""
	public var json: Data!
	public let name = Field<String>("name")
	public let url = Field<String>("url")
	public init() {}
}

extension User {
	public static var currentUser: User? {
		var userDefaults: NSUserDefaults
		#if TARGET_IS_EXTENSION
			userDefaults = NSUserDefaults(suiteName: APPGROUP_USER)!
		#else
			userDefaults = NSUserDefaults.standardUserDefaults()
		#endif
		if let object = userDefaults.objectForKey("user") as? [String: AnyObject] {
			let user = User(json: Data(object))
			return user
		}
		return nil
	}

	public static func currentUser(block: (User?, ErrorType?) -> Void) {
		if let user = currentUser, token = user.json.value("sessionToken").string {
			block(user, nil)
			print("returned user may not be valid server side")
			Parse.updateSession(token)
			Parse.Get("users/me", nil).response { (_, error) in
				if let error = error {
					print("session login failed \(user.username) \(error)")
					block(user, error)
				}
			}
			return
		}
		block(nil, nil)
	}

	public static func logIn(username: String, password: String, callback: (User?, ErrorType?) -> Void) {
		Parse.updateSession(nil)
		Parse.Get("login", ["username": username, "password": password]).response { (json, error) in
			if let error = error {
				return callback(nil, error)
			}
			if let json = json {
				let user = User(json: Data(json))
				if let token = user.json.value("sessionToken").string {
					NSUserDefaults.standardUserDefaults().setObject(json, forKey: "user")
					NSUserDefaults.standardUserDefaults().synchronize()
					//					let defaults = NSUserDefaults(suiteName: APPGROUP_USER)
					//					defaults?.setObject(json, forKey: "user")
					Parse.updateSession(token)
					print("logIn user \(json)")
					dispatch_async(dispatch_get_main_queue()) {
						callback(user, nil)
					}
				} else {
					callback(nil, ParseError.SessionFailure)
				}
			}
		}
	}

	public static func logOut() {
		//		let defaults = NSUserDefaults(suiteName: APPGROUP_USER)
		//		defaults?.removeObjectForKey("user")
		NSUserDefaults.standardUserDefaults().removeObjectForKey("user")
		NSUserDefaults.standardUserDefaults().synchronize()
		Parse.updateSession(nil)
		Parse.Post("logout", nil).response { _ in }
	}

	public static func signUp(username: String, password: String, extraInfo: [String: ComparableKeyType]? = nil, callback: (User?, ErrorType?) -> Void) {
		Parse.updateSession(nil)
		let o = operation().set("username", value: username).set("password", value: password)
		if let info = extraInfo {
			for (k, v) in info {
				o.set(k, value: v)
			}
		}
		o.save { (user, error) in
			if let user = user {
				if let token = user.json.value("sessionToken").string {
					NSUserDefaults.standardUserDefaults().setObject(user.json.raw, forKey: "user")
					NSUserDefaults.standardUserDefaults().synchronize()
					Parse.updateSession(token)
					print("signUp user \(user)")
					callback(user, error)
				} else {
					self.logIn(username, password: password, callback: callback)
				}
			} else {
				print("error \(error)")
				return callback(nil, error)
			}
		}
	}
}

extension File {
	public static func uploadImage(data: NSData, callback: (File?, ErrorType?) -> Void) {
		Parse.UploadData("files/pic.jpg", data).response { (json, error) in
			if let json = json {
				callback(File(json: Data(json)), error)
			} else {
				callback(nil, error)
			}
		}
	}
	public static func uploadImage(file: NSURL, callback: (File?, ErrorType?) -> Void) {
		Parse.UploadFile("files/pic.jpg", file).response { (json, error) in
			if let json = json {
				callback(File(json: Data(json)), error)
			} else {
				callback(nil, error)
			}
		}
	}
}

extension RelationsCache {
	public static func of<T: ParseObject>(type: T.Type, key: String, closure: (ManyToMany) -> Void) {
		if let user = User.currentUser {
			of(type, key: key, to: user, closure: closure)
		}
	}
	public static func of<U: ParseObject>(key: String, toType: U.Type, closure: (ManyToMany) -> Void) {
		if let user = User.currentUser {
			of(Pointer(object: user), key: key, toClass: U.className, closure: closure)
		}
	}
}

extension ClassOperations {
	public func setSecurity(readwrite: User) -> Self {
		return operation(.SetSecurity(readwrite.objectId))
	}
}

//MARK: Push

extension NSData {
	public var hexadecimalString: NSString {
		var bytes = [UInt8](count: length, repeatedValue: 0)
		getBytes(&bytes, length: length)

		let hexString = NSMutableString()
		for byte in bytes {
			hexString.appendFormat("%02x", UInt(byte))
		}

		return NSString(string: hexString)
	}
}

extension Installation {
	static var currentInstallation: Installation?

	public static func register(deviceToken: NSData, channels: [String], otherInfo: ((ClassOperations<Installation>) -> Void)? = nil) {
		let op = operation()
			.set("deviceType", value: "ios")
			.set("deviceToken", value: deviceToken.hexadecimalString)
			.set("channels", value: channels)
		otherInfo?(op)
		op.save { (installation, error) in
			if let installation = installation {
				self.currentInstallation = installation
				print("current installation \(installation.json)")
			}
		}
	}

	public static func clearBadge() {
		if let installation = Installation.currentInstallation {
			installation.operation().set("badge", value: 0).update { _ in }
		}
	}
}

public struct Push {
	public static func send(data: [String: AnyObject], query: Query<Installation>) {
		var _where: [String: AnyObject] = [:]
		query.composeQuery(&_where)
		print("push where = \(_where)")
		Parse.Post("push", ["where": _where, "data": data]).response { _ in }
	}
}
