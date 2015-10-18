//
//  ParseSystemObjects.swift
//  Parse
//
//  Created by Rex Sheng on 3/9/15.
//  Copyright (c) 2015 Rex Sheng. All rights reserved.
//

import UIKit

let APPGROUP_USER = "AppGroupUser"

public struct User: ParseObject {
	public static var className: String { return "_User" }
	public var json: Data
	public var objectId: String {
		return json.objectId
	}
	public init(json: Data) {
		self.json = json
	}
	var username: String {
		return json.value("username").string!
	}
}

public struct Installation: ParseObject {
	public static var className: String { return "_Installation" }
	public var json: Data
	public init(json: Data) {
		self.json = json
	}
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
	
	public static func currentUser(block: (User?, NSError?) -> Void) {
		if let user = currentUser {
			if let token = user.json.value("sessionToken").string {
				block(user, nil)
				print("returned user may not be valid server side")
				Client.loginSession(token) { error in
					if let error = error {
						print("session login failed \(user.username) \(error)")
						block(user, error)
					}
				}
				return
			}
		}
		block(nil, nil)
	}
	
	public static func logIn(username: String, password: String, callback: (User?, NSError?) -> Void) {
		Client.updateSession(nil)
		Client.request(.GET, "/login", ["username": username, "password": password]) { (json, error) in
			if let error = error {
				return callback(nil, error)
			}
			if let json = json {
				let user = User(json: Data(json))
				if let token = user.json.value("sessionToken").string {
					NSUserDefaults.standardUserDefaults().setObject(json, forKey: "user")
					NSUserDefaults.standardUserDefaults().synchronize()
					let defaults = NSUserDefaults(suiteName: APPGROUP_USER)
					defaults?.setObject(json, forKey: "user")
					Client.updateSession(token)
					print("logIn user \(json)")
					dispatch_async(dispatch_get_main_queue()) {
						callback(user, nil)
					}
				} else {
					callback(nil, NSError(domain: ParseErrorDomain, code: 206, userInfo: [NSLocalizedDescriptionKey: "Failed to establish session"]))
				}
			}
		}
	}
	
	public static func logOut() {
		let defaults = NSUserDefaults(suiteName: APPGROUP_USER)
		defaults?.removeObjectForKey("user")
		NSUserDefaults.standardUserDefaults().removeObjectForKey("user")
		NSUserDefaults.standardUserDefaults().synchronize()
		Client.updateSession(nil)
	}
	
	public static func signUp(username: String, password: String, extraInfo: [String: ComparableKeyType]? = nil, callback: (User?, NSError?) -> Void) {
		Client.updateSession(nil)
		let operation = ClassOperations<User>().set("username", value: username).set("password", value: password)
		if let info = extraInfo {
			for (k, v) in info {
				operation.set(k, value: v)
			}
		}
		operation.save { (user, error) in
			if let error = error {
				print("error \(error)")
				return callback(nil, error)
			}
			if let user = user {
				if let token = user.json.value("sessionToken").string {
					NSUserDefaults.standardUserDefaults().setObject(user.json.raw, forKey: "user")
					let defaults = NSUserDefaults(suiteName: APPGROUP_USER)
					defaults?.setObject(user.json.raw, forKey: "user")
					NSUserDefaults.standardUserDefaults().synchronize()
					Client.updateSession(token)
					print("signUp user \(user)")
					callback(user, error)
				} else {
					self.logIn(username, password: password, callback: callback)
				}
			}
		}
	}
	
	public static func uploadImage(data: NSData, callback: (String?, NSError?) -> Void) {
		Client.request(.POST, "/files/pic.jpg", data) { (json, error) -> Void in
			if let error = error {
				return callback(nil, error)
			}
			if let json = json {
				callback(json["url"] as? String, error)
			}
		}
	}
}

extension Relations {
	public static func of<T: ParseObject>(type: T.Type, key: String, closure: (Relation) -> Void) {
		if let user = User.currentUser {
			of(type, key: key, to: user, closure: closure)
		}
	}
	public static func of<U: ParseObject>(key: String, toType: U.Type, closure: (Relation) -> Void) {
		if let user = User.currentUser {
			of(Pointer(object: user), key: key, toClass: U.className, closure: closure)
		}
	}
}

extension User {
	
	public func addRelation<U: ParseObject>(key: String, to: U) -> ObjectOperations<User> {
		return Parse<User>.operation(objectId).addRelation(key, to: to)
	}
	
	public func removeRelation<U: ParseObject>(key: String, to: U) -> ObjectOperations<User> {
		return Parse<User>.operation(objectId).removeRelation(key, to: to)
	}
	
	public func relatedTo<U: ParseObject>(object: U, key: String) -> Query<User> {
		return Query<User>(constraints: .RelatedTo(key, Pointer(object: object)))
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
		let operation = Parse<Installation>.operation()
			.set("deviceType", value: "ios")
			.set("deviceToken", value: deviceToken.hexadecimalString)
			.set("channels", value: channels)
		otherInfo?(operation)
		operation.save { (installation, error) in
			if let installation = installation {
				self.currentInstallation = installation
				print("current installation \(installation.json)")
			}
		}
	}
	
	func op() -> ObjectOperations<Installation> {
		return Parse<Installation>.operation(json.objectId)
	}
	
	public static func clearBadge() {
		if let installation = Installation.currentInstallation {
			installation.op().set("badge", value: 0).update { _ in }
		}
	}
}

public struct Push {
	public static func send(data: [String: AnyObject], query: Query<Installation>) {
		var _where: [String: AnyObject] = [:]
		query.composeQuery(&_where)
		print("push where = \(_where)")
		Client.request(.POST, "/push", ["where": _where, "data": data]) { _ in }
	}
}
