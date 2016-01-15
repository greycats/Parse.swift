//
//  Client.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

import Alamofire
typealias Method = Alamofire.Method

public let ParseErrorDomain = "co.interactivelabs.parse"


//MARK: - Dispatch

var clientCreated = false

public struct Client {
	static var manager_init_group: dispatch_group_t = {
		clientCreated = true

		var group = dispatch_group_create()
		dispatch_group_enter(group)
		return group
	}()

	static var manager: Manager?

	static func request(method: Method, _ path: String, _ parameters: [String: AnyObject]?, _ closure: ([String: AnyObject]?, NSError?) -> Void) {
		let pathString = "https://api.parse.com/1\(path)"
		var encoding: ParameterEncoding
		switch method {
		case .POST, .PUT:
			encoding = .JSON
		default:
			encoding = .URL
		}
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			let request = self.manager!.request(method, pathString, parameters: parameters, encoding: encoding)
			request.responseJSON { res in
				if let object = res.result.value as? [String: AnyObject] {
					if object["error"] != nil && object["code"] != nil {
						closure(nil, NSError(domain: ParseErrorDomain, code: object["code"] as! Int, userInfo: [NSLocalizedDescriptionKey: object["error"] as! String]))
						return
					}
					closure(object, res.result.error)
				} else {
					closure(nil, res.result.error)
				}
			}
			return
		}
	}

	static func request(method: Method, _ path: String, _ data: NSData, _ closure: ([String: AnyObject]?, NSError?) -> Void) {
		let pathString = "https://api.parse.com/1\(path)"
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) { () -> Void in
			let request = self.manager!.upload(method, pathString, data: data)
			request.responseJSON(options: []) { res in
				if let object = res.result.value as? [String: AnyObject] {
					if object["error"] != nil && object["code"] != nil {
						closure(nil, NSError(domain: ParseErrorDomain, code: object["code"] as! Int, userInfo: [NSLocalizedDescriptionKey: object["error"] as! String]))
						return
					}
					closure(object, res.result.error)
				} else {
					closure(nil, res.result.error)
				}
			}
		}
	}

	static func updateSession(token: String?) {
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			if var headers = self.manager!.session.configuration.HTTPAdditionalHeaders {
				headers["X-Parse-Session-Token"] = token
				self.manager!.session.configuration.HTTPAdditionalHeaders = headers
			}
		}
	}

	static func loginSession(token: String, block: (NSError?) -> Void) {
		updateSession(token)
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			self.request(.GET, "/users/me", nil) { (json, error) in
				block(error)
			}
		}
	}

	public static func setup(applicationId applicationId: String, restKey: String?, masterKey: String? = nil) {
		let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
		var headers = ["X-Parse-Application-Id": applicationId]
		if let restKey = restKey {
			headers["X-Parse-REST-API-Key"] = restKey
		} else if let masterKey = masterKey {
			headers["X-Parse-Master-Key"] = masterKey
		}
		var userDefaults: NSUserDefaults
		#if TARGET_IS_EXTENSION
			userDefaults = NSUserDefaults(suiteName: APPGROUP_USER)!
		#else
			userDefaults = NSUserDefaults.standardUserDefaults()
		#endif
		if let object = userDefaults.objectForKey("user") as? [String: AnyObject] {
			if let token = object["sessionToken"] as? String {
				headers["X-Parse-Session-Token"] = token
			}
		}
		configuration.HTTPAdditionalHeaders = headers
		self.manager = Manager(configuration: configuration)
		dispatch_group_leave(manager_init_group)
	}

	public static func trackAppOpen() {
		request(.POST, "/events/AppOpened", [:]) { (json, error) in
			print("trackAppOpen error = \(error)")
		}
	}
}

func path(className: String, objectId: String? = nil) -> String {
	var path: String
	switch className {
	case "_User":
		path = "/users"
	case "_Installation":
		path = "/installations"
	default:
		path = "/classes/\(className)"
	}
	if let objectId = objectId {
		path += "/\(objectId)"
	}
	return path
}

public func parseFunction(name: String, parameters: [String: AnyObject], done: ([String: AnyObject]?, NSError?) -> Void) {
	Client.request(.POST, "/functions/\(name)", parameters, done)
}
