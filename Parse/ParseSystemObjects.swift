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

public struct Config {
	public static func get(closure: [String: AnyObject] -> ()) {
		Parse.Get("config", nil).response { (data, error) in
			if let data = data?["params"] as? [String: AnyObject] {
				closure(data)
			} else {
				closure([:])
			}
		}
	}
}

extension User {
	public static var currentUser: User? {
		return load()
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

	private static func load() -> User? {
		if let defaults = NSUserDefaults(suiteName: "parse"), object = defaults.objectForKey("user") as? [String: AnyObject] {
			var data = Data(object)
			if let Cacheable = User.self as? Cacheable.Type {
				let cache = IndividualDataCache(expireAfter: Cacheable.expireAfter, className: User.className)
				if let cachedData = try? cache.get(data.objectId) {
					print("return cached user instead of which in user defaults")
					data = cachedData
				}
			}
			let user = User(json: data)
			return user
		}
		return nil
	}

	private func persist(@noescape callback: (User?, ErrorType?) -> ()) {
		if let token = json.value("sessionToken").string {
			if let defaults = NSUserDefaults(suiteName: "parse") {
				defaults.setObject(json.raw, forKey: "user")
				defaults.synchronize()
			}
			Parse.updateSession(token)
			print("logIn user \(json)")
			callback(self, nil)
		} else {
			callback(nil, ParseError.SessionFailure)
		}
	}

	public static func logIn(username: String, password: String, callback: (User?, ErrorType?) -> Void) {
		Parse.updateSession(nil)
		Parse.Get("login", ["username": username, "password": password]).one { (user: User?, error) in
			if let user = user {
				user.persist(callback)
			} else {
				callback(nil, error)
			}
		}
	}

	public static func logOut() {
		if let defaults = NSUserDefaults(suiteName: "parse") {
			defaults.removeObjectForKey("user")
			defaults.synchronize()
		}
		Parse.updateSession(nil)
		Parse.Post("logout", nil).response { _ in }
	}

	public static func signUp(username: String, password: String, @noescape extraInfoBuilder: Operations<User> -> () = {_ in}, callback: (User?, ErrorType?) -> Void) {
		Parse.updateSession(nil)
		let o = operation().set("username", value: username).set("password", value: password)
		extraInfoBuilder(o)
		o.save { (user, error) in
			if let _ = user {
				logIn(username, password: password, callback: callback)
			} else {
				print("error \(error)")
				callback(nil, error)
			}
		}
	}
}

extension Data {
	public func file(key: String) -> File? {
		if let value = raw[key] as? [String: String] where value["__type"] == "File" {
			return File(json: Data(value))
		}
		return nil
	}
}

extension File {
	public static func uploadJPEGImage(data: NSData, callback: (File?, ErrorType?) -> Void) {
		let path = "files/image.jpg"
		let mime = "image/jpeg"
		Parse.UploadData(path, mime, data).response { (json, error) in
			if let json = json {
				callback(File(json: Data(json)), error)
			} else {
				callback(nil, error)
			}
		}
	}

	public static func uploadImage(file: NSURL, callback: (File?, ErrorType?) -> Void) {
		let path = "files/\(file.lastPathComponent!)"
		let mime: String
		if path.hasSuffix(".png") {
			mime = "image/png"
		} else if path.hasSuffix(".jpg") || path.hasSuffix(".jpeg") {
			mime = "image/jpeg"
		} else {
			mime = "application/octet-stream"
		}
		Parse.UploadFile(path, mime, file).response { (json, error) in
			if let json = json {
				callback(File(json: Data(json)), error)
			} else {
				callback(nil, error)
			}
		}
	}
}

extension Operations {
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

	public static func register(deviceToken: NSData, channels: [String], otherInfo: ((Operations<Installation>) -> Void)? = nil) {
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
			installation.operation().set("badge", value: 0).save { _ in }
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
