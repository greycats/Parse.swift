//
//  Parse.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

import Alamofire
typealias Method = Alamofire.Method

public enum ParseError: ErrorType {
	case SessionFailure
	case UncategorizedError(code: Int, message: String)
}

//MARK: - Dispatch

public typealias Response = ([String: AnyObject]?, ErrorType?) -> ()
var clientCreated = false
public enum Parse: URLRequestConvertible {
	private static var hostPrefix: String!
	private static var parseHeaders: [String: String]!
	private static var token: String?

	case Get(String, [String: AnyObject]?)
	case Post(String, [String: AnyObject]?)
	case Put(String, [String: AnyObject]?)
	case Delete(String, [String: AnyObject]?)
	case UploadData(String, String, NSData)
	case UploadFile(String, String, NSURL)

	public var URLRequest: NSMutableURLRequest {
		let _parameters: [String: AnyObject]?
		var method: Alamofire.Method = .POST
		let _path: String
		switch self {
		case .Get(let path, let parameters):
			_path = path
			method = .GET
			_parameters = parameters
		case .Put(let path, let parameters):
			_path = path
			method = .PUT
			_parameters = parameters
		case .Post(let path, let parameters):
			_path = path
			_parameters = parameters
		case .Delete(let path, let parameters):
			_path = path
			method = .DELETE
			_parameters = parameters
		case .UploadData(let path, _, _):
			_path = path
			method = .POST
			_parameters = nil
		case .UploadFile(let path, _, _):
			_path = path
			method = .POST
			_parameters = nil
		}
		let encoding: Alamofire.ParameterEncoding
		switch method {
		case .POST, .PUT:
			encoding = .JSON
		default:
			encoding = .URL
		}

		let URL = NSURL(string: Parse.hostPrefix)!
		let URLRequest = NSMutableURLRequest(URL: URL.URLByAppendingPathComponent(_path))
		URLRequest.HTTPMethod = method.rawValue
		for (k, v) in Parse.parseHeaders {
			URLRequest.setValue(v, forHTTPHeaderField: k)
		}
		if let token = Parse.token {
			URLRequest.setValue(token, forHTTPHeaderField: "X-Parse-Session-Token")
		}
		switch self {
		case .UploadData(_, let mime, _):
			URLRequest.setValue(mime, forHTTPHeaderField: "Content-Type")
		case .UploadFile(_, let mime, _):
			URLRequest.setValue(mime, forHTTPHeaderField: "Content-Type")
		default:
			break
		}
		let req = encoding.encode(URLRequest, parameters: _parameters).0
		return req
	}

	public static func setup(applicationId applicationId: String, restKey: String?, masterKey: String? = nil) {
		hostPrefix = "https://api.parse.com/1/"
		parseHeaders = ["X-Parse-Application-Id": applicationId]
		if let restKey = restKey {
			parseHeaders["X-Parse-REST-API-Key"] = restKey
		} else if let masterKey = masterKey {
			parseHeaders["X-Parse-Master-Key"] = masterKey
		}
		var userDefaults: NSUserDefaults
		#if TARGET_IS_EXTENSION
			userDefaults = NSUserDefaults(suiteName: APPGROUP_USER)!
		#else
			userDefaults = NSUserDefaults.standardUserDefaults()
		#endif
		if let object = userDefaults.objectForKey("user") as? [String: AnyObject] {
			if let token = object["sessionToken"] as? String {
				parseHeaders["X-Parse-Session-Token"] = token
			}
		}
	}

	public static func updateSession(token: String?) {
		self.token = token
	}

	public func one<T: ParseObject>(closure: (T?, ErrorType?) -> ()) {
		response { json, error in
			if let json = json {
				closure(T(json: Data(json)), error)
			} else {
				closure(nil, error)
			}
		}
	}

	public func response(injector: Response -> Bool, closure: Response) {
		if injector(closure) { return }
		request(self).response(closure)
	}

	public func response(closure: ([String: AnyObject]?, ErrorType?) -> ()) {
		switch self {
		case .UploadFile(_, _, let data):
			upload(self, file: data).response(closure)
		case .UploadData(_, _, let data):
			upload(self, data: data).response(closure)
		default:
			request(self).response(closure)
		}
	}
}

extension Alamofire.Request {

	private func response(closure: ([String: AnyObject]?, ErrorType?) -> ()) {
		responseJSON { response in
			if let object = response.result.value as? [String: AnyObject] {
				if object["error"] != nil && object["code"] != nil {
					closure(nil, ParseError.UncategorizedError(code: object["code"] as! Int, message: object["error"] as! String))
					return
				}
				closure(object, response.result.error)
			} else {
				closure(nil, response.result.error)
			}
		}
	}
}

public func parseFunction(name: String, parameters: [String: AnyObject], done: ([String: AnyObject]?, ErrorType?) -> Void) {
	Parse.Post("functions/\(name)", parameters).response(done)
}
