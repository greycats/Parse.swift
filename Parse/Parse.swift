//
//  Parse.swift
//
//  Created by Rex Sheng on 2/4/15.
//
//

import Foundation
import Alamofire
import SwiftyJSON

private let ParseErrorDomain = "co.interactivelabs.parse"

var manager_init_group: dispatch_group_t = {
	var group = dispatch_group_create()
	dispatch_group_enter(group)
	return group
	}()

var parseManager: Manager?

func parseRequest(method: Alamofire.Method, path: String, parameters: [String: AnyObject]?, closure: (JSON, NSError?) -> Void) {
	var pathString = "https://api.parse.com/1\(path)"
	var encoding: ParameterEncoding
	switch method {
	case .POST, .PUT:
		encoding = .JSON
	default:
		encoding = .URL
	}
	dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
		parseManager!.request(method, pathString, parameters: parameters, encoding: encoding)
			.responseJSON { (req, res, json, error) in
				if let object = json as? [String: AnyObject] {
					if object["error"] != nil && object["code"] != nil {
						closure(JSON.nullJSON, NSError(domain: ParseErrorDomain, code: object["code"] as Int, userInfo: object))
						return
					}
					closure(JSON(object), error)
				} else {
					closure(JSON.nullJSON, error)
				}
		}
		return
	}
}

public func setup(#applicationId: String, #restKey: String?, masterKey: String? = nil) {
	var configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
	var headers = ["X-Parse-Application-Id": applicationId]
	if let restKey = restKey {
		headers["X-Parse-REST-API-Key"] = restKey
	} else if let masterKey = masterKey {
		headers["X-Parse-Master-Key"] = masterKey
	}
	configuration.HTTPAdditionalHeaders = headers
	parseManager = Manager(configuration: configuration)
	dispatch_group_leave(manager_init_group)
}

public func trackAppOpen() {
	parseRequest(.POST, "/events/AppOpened", [:]) { (json, error) in
		println("trackAppOpen error = \(error)")
	}
}

public protocol ParseObject {
	init(json: JSON)
}

func pointerToClass(name: String, objectId: String) -> [String: String] {
	return ["__type": "Pointer", "className": name, "objectId": objectId]
}

public struct Search {
	var memcache: [String: AnyObject]? = nil
	var memcacheKey: String? = nil
}

public class Parse<T: ParseObject> {
	
	let name: String
	
	var search = Search()
	
	public init(_ className: String) {
		name = className
	}
	
	public func query() -> Query<T> {
		return Query<T>(self)
	}
	
	public func query(constraints: Constraints) -> Query<T> {
		return Query<T>(self, constraints: constraints)
	}
	
	func insert() {
		
	}
	
	func delete(ids: [String], done: dispatch_block_t) {
	}
	
	func saveAll(objects: [AnyObject], done: dispatch_block_t) {
	}
	
	func function(name: String, parameters: [String: AnyObject], done: dispatch_block_t) {
	}
}

public enum Constraint {
	case GreaterThan(key: String, object: AnyObject)
	case LessThan(key: String, object: AnyObject)
	case EqualTo(key: String, object: AnyObject)
	case MatchQuery(key: String, matchKey: String, inQuery: Constraints, search: Search)
	case DoNotMatchQuery(key: String, dontMatchKey: String, inQuery: Constraints, search: Search)
	case MatchRegex(key: String, match: NSRegularExpression)
	case Or(left: Constraints, right: Constraints)
	case In(key: String, right: [JSON])
	case NotIn(key: String, right: [JSON])
	
	func whereClause(var param: [String: AnyObject]) {
		switch self {
		case .GreaterThan(let key, let object):
			param[key] = ["$gt": object]
		case .LessThan(let key, let object):
			param[key] = ["$lt": object]
		case .EqualTo(let key, let object):
			param[key] = object as AnyObject
		case .MatchQuery(let key, let matchKey, let inQuery, let search):
			param[key] = ["$select": ["key": matchKey, "query": ["className": inQuery.className, "where": inQuery.whereClause()]]]
		case .DoNotMatchQuery(let key, let dontMatchKey, let inQuery, let search):
			param[key] = ["$dontSelect": ["key": dontMatchKey, "query": ["className": inQuery.className, "where": inQuery.whereClause()]]]
		case .MatchRegex(let key, let match):
			var options = ""
			if match.options & .CaseInsensitive == .CaseInsensitive {
				options += "i"
			}
			param[key] = ["$regex": match.pattern, "$options": options]
		case .Or(let left, let right):
			param["$or"] = [left.whereClause(), right.whereClause()]
		case .In(let left, let right):
			param["$in"] = right.map({ $0.object})
		case .NotIn(let left, let right):
			param["$nin"] = right.map({ $0.object})
		}
	}
}

public struct Constraints {
	var inner: [Constraint] = []
	let className: String
	
	init(className: String) {
		self.className = className
	}
	
	mutating func append(constraint: Constraint) {
		inner.append(constraint)
	}
	
	func whereClause() -> [String: AnyObject] {
		var param: [String: AnyObject] = [:]
		for constraint in inner {
			constraint.whereClause(param)
		}
		return param
	}
}

public class Query<T: ParseObject> {
	
	var constraints: Constraints
	var parameters: [String: AnyObject] = [:]
	var path: String
	var object: Parse<T>
	var order: String?
	var limit: Int = 100
	var skip: Int = 0
	
	var fetchesCount = false
	
	init(_ object: Parse<T>) {
		self.constraints = Constraints(className: object.name)
		self.object = object
		path = "/classes/\(object.name)"
	}
	
	convenience init(_ object: Parse<T>, constraints: Constraints) {
		self.init(object)
		self.constraints.inner = constraints.inner
	}
	
	public func constraint(constraint: Constraint) -> Self {
		constraints.append(constraint)
		return self
	}
	
	public func whereKey(key: String, equalTo object: String) -> Self {
		constraints.append(.EqualTo(key: key, object: object as AnyObject))
		return self
	}
	
	public func whereKey(key: String, equalTo object: AnyObject) -> Self {
		constraints.append(.EqualTo(key: key, object: object))
		return self
	}
	
	public func whereKey(key: String, greaterThan: AnyObject) -> Self {
		return constraint(.GreaterThan(key: key, object: greaterThan))
	}
	
	public func whereKey(key: String, lessThan: AnyObject) -> Self {
		return constraint(.LessThan(key: key, object: lessThan))
	}
	
	public func whereKey<U: ParseObject>(key: String, matchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.MatchQuery(key: key, matchKey: matchKey, inQuery: inQuery.constraints, search: inQuery.object.search))
	}
	
	public func whereKey<U: ParseObject>(key: String, dontMatchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.DoNotMatchQuery(key: key, dontMatchKey: dontMatchKey, inQuery: inQuery.constraints, search: inQuery.object.search))
	}
	
	public func whereKey(key: String, match: NSRegularExpression) -> Self {
		return constraint(.MatchRegex(key: key, match: match))
	}
	
	public func includeKeys(exp: String) -> Self {
		parameters["keys"] = exp
		return self
	}
	
	public func skip(skip: Int) -> Self {
		self.skip = skip
		parameters["skip"] = skip
		return self
	}
	
	public func order(order: String) -> Self {
		self.order = order
		parameters["order"] = order
		return self
	}
	
	public func limit(limit: Int) -> Self {
		self.limit = limit
		parameters["limit"] = limit
		return self
	}
	
	public func getRaw(closure: (JSON, NSError?) -> Void) {
		if self.object.search.searchLocal(self, closure: closure) {
			return
		}
		
		let whereExp = constraints.whereClause()
		if whereExp.count > 0 {
			parameters["where"] = JSON(whereExp).rawString()
		}
		println("sending \(parameters) to \(path)")
		parseRequest(.GET, path, parameters, closure)
	}
	
	public func get(closure: ([T], NSError?) -> Void) {
		getRaw { (json, error) in
			let array = json["results"].arrayValue
			closure(array.map({ T(json: $0) }), error)
		}
	}
	
	public func count(closure: (Int, NSError?) -> Void) {
		fetchesCount = true
		limit(1)
		parameters["count"] = 1
		getRaw { (json, error) in
			closure(json["count"].intValue, error)
		}
	}
	
	public func getFirst(closure: (T?, NSError?) -> Void) {
		parameters["limit"] = 1
		getRaw { (json, error) in
			let array = json["results"].arrayValue
			if let first = array.first {
				closure(T(json: first), error)
			} else {
				closure(nil, error)
			}
		}
	}
}

public func ||<T>(left: Query<T>, right: Query<T>) -> Query<T> {
	let query = Query<T>(left.object)
	query.constraints.append(.Or(left: left.constraints, right: right.constraints))
	return query
}

public struct User {
	
	let json: JSON
	
	init(_ json: JSON) {
		self.json = json
	}
	
	var username: String {
		return json["username"].string!
	}
	
	func loginSession(block: (NSError?) -> Void) {
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			if var headers = parseManager!.session.configuration.HTTPAdditionalHeaders {
				headers["X-Parse-Session-Token"] = self.json["sessionToken"].string
				parseManager!.session.configuration.HTTPAdditionalHeaders = headers
			}
			parseRequest(.GET, "/users/me", nil) { (json, error) in
				block(error)
			}
		}
	}
	
	public static func currentUser(block: (User?, NSError?) -> Void) {
		if let object: AnyObject = NSUserDefaults.standardUserDefaults().objectForKey("user") {
			let user = User(JSON(object))
			block(user, nil)
			println("returned user may not be valid server side")
			user.loginSession { error in
				if error != nil {
					println("login session \(user.username)")
					block(user, error)
				}
			}
		} else {
			block(nil, nil)
		}
	}
	
	public static func login(username: String, password: String, callback: (User?, NSError?) -> Void) {
		parseRequest(.GET, "/login", ["username": username, "password": password]) { (json, error) in
			if error != nil {
				return callback(nil, error)
			}
			NSUserDefaults.standardUserDefaults().setObject(json.object, forKey: "user")
			NSUserDefaults.standardUserDefaults().synchronize()
			println("login user \(json)")
			callback(User(json), error)
		}
	}
	
	public static func signup(username: String, password: String, extraInfo: [String: AnyObject]? = nil, callback: (User?, NSError?) -> Void) {
		var param: [String: AnyObject] = ["username": username, "password": password]
		if var info = extraInfo {
			for (k, v) in info {
				param.updateValue(v, forKey: k)
			}
		}
		parseRequest(.POST, "/users", param) { (json, error) in
			if error != nil {
				return callback(nil, error)
			}
			
			var user = json.object as [String: AnyObject]
			user["username"] = username
			if var info = extraInfo {
				for (k, v) in info {
					user[k] = v
				}
			}
			NSUserDefaults.standardUserDefaults().setObject(user, forKey: "user")
			NSUserDefaults.standardUserDefaults().synchronize()
			let u = JSON(user)
			println("signup user \(u)")
			callback(User(u), error)
		}
	}
}

// local search
extension Search {
	
	func keys(matches: String, constraints: Constraints) -> [JSON] {
		var results: [JSON] = []
		if let cache = memcache {
			for (key, object) in cache {
				if let object = object as? [String: AnyObject] {
					let json = JSON(object)
					var supported = false
					if constraints.match(json) {
						results.append(json[matches])
					}
				}
			}
		}
		return results
	}
	
	func searchLocal<T: ParseObject>(query: Query<T>, closure: (JSON, NSError?) -> Void) -> Bool {
		query.constraints.replaceSubQueries()
		if let cache = self.memcache {
			dispatch_async(dispatch_get_global_queue(0, 0)) {
				var results: [JSON] = []
				var count = 0
				for (key, object) in cache {
					if let object = object as? [String: AnyObject] {
						let object = JSON(object)
						if query.constraints.match(object) {
							count++
							if !query.fetchesCount {
								results.append(object)
								//TOOD
							}
						}
					}
				}
				
				if let order = query.order {
					//TODO
					sort(&results, { (a, b) in
						return a[order] < b[order]
					})
					
					if results.count > query.limit {
						results = Array(results[0..<query.limit])
					}
				}
				
				dispatch_async(dispatch_get_main_queue()) {
					var result: [String: AnyObject] = [:]
					if query.fetchesCount {
						result["count"] = count
					} else {
						result["results"] = results.map({ $0.object })
					}
					closure(JSON(result), nil)
				}
			}
			return true
		}
		return false
	}
}

extension Constraint {
	
	func match(json: JSON) -> Bool {
		switch self {
		case .EqualTo(let key, let right):
			return json[key] == JSON(right)
		case .GreaterThan(let key, let right):
			return json[key] > JSON(right)
		case .LessThan(let key, let right):
			return json[key] > JSON(right)
		case .MatchRegex(let key, let regexp):
			let string = json[key].stringValue
			return regexp.firstMatchInString(string, options: nil, range: NSMakeRange(0, string.utf16Count)) != nil
		case .In(let key, let keys):
			return contains(keys, json[key])
		case .NotIn(let key, let keys):
			return !contains(keys, json[key])
		case .Or(let left, let right):
			return left.match(json) || right.match(json)
		default:
			return false
		}
	}
}

extension Constraint: Printable {
	public var description: String {
		switch self {
		case .EqualTo(let key, let right):
			return "\(key) equal to \(right)"
		case .GreaterThan(let key, let right):
			return "\(key) greater than \(right)"
		case .LessThan(let key, let right):
			return "\(key) less than \(right)"
		case .MatchRegex(let key, let regexp):
			return "\(key) matches \(regexp.pattern)"
		case .In(let key, let keys):
			return "\(key) in \(keys)"
		case .NotIn(let key, let keys):
			return "\(key) not in \(keys)"
		case .Or(let left, let right):
			return "\(left) or \(right)"
		case .MatchQuery(let key, let matchKey, let inQuery, let search):
			return "\(key) matches \(matchKey) from \(inQuery.className) where \(inQuery.whereClause())"
		case .DoNotMatchQuery(let key, let dontMatchKey, let inQuery, let search):
			return "\(key) doesn't match \(dontMatchKey) from \(inQuery.className) where \(inQuery.whereClause())"
		}
	}
}

extension Constraints {
	
	mutating func replaceSubQueries() {
		
		var replaced = false
		for (index, constraint) in enumerate(inner) {
			switch constraint {
			case .MatchQuery(let key, let matchKey, let constraints, let search):
				let keys = search.keys(matchKey, constraints: constraints)
				inner[index] = Constraint.In(key: key, right: keys)
				replaced = true
			case .DoNotMatchQuery(let key, let dontMatchKey, let constraints, let search):
				let keys = search.keys(dontMatchKey, constraints: constraints)
				inner[index] = Constraint.NotIn(key: key, right: keys)
				replaced = true
			default:
				continue
			}
		}
		
		if replaced {
			println("replaced subqueries with in/notin queries \(inner)")
		}
	}
	
	func match(json: JSON) -> Bool {
		for constraint in inner {
			let match = constraint.match(json)
			if !match {
				return false
			}
		}
		return true
	}
}

extension Parse {
	
	func paging(group: dispatch_group_t, skip: Int = 0, block: (JSON) -> Void) {
		dispatch_group_enter(group)
		self.query().limit(1000).skip(skip).getRaw { (objects, error) -> Void in
			if objects.count == 1000 {
				self.paging(group, skip: skip + 1000, block: block)
			}
			block(objects)
			dispatch_group_leave(group)
		}
	}
	
	func each(group: dispatch_group_t, block: (JSON) -> Void) {
		self.paging(group, skip: 0) { objects in
			for object in objects["results"].arrayValue {
				block(object)
			}
		}
	}
	
	func eachPage(group: dispatch_group_t, block: (JSON) -> Void) {
		self.paging(group, skip: 0) { objects in
			block(objects)
		}
	}
	
	func loadCache() -> JSON? {
		let key = "v1.\(name).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			let file = root.stringByAppendingPathComponent(key)
			println("loading from file \(file)")
			if let data = NSData(contentsOfFile: file) {
				let json = JSON(data: data)
				return json
			}
		}
		return nil
	}
	
	func writeCache(json: JSON) {
		let key = "v1.\(name).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			json.rawData()?.writeToFile(root.stringByAppendingPathComponent(key), atomically: true)
			println("\(name) data wrote to \(root.stringByAppendingPathComponent(key))")
		}
	}
	
	public func persistToLocal(maxAge: NSTimeInterval = 86400 * 7, primaryKey: String = "objectId", done: (([String: AnyObject]) -> Void)? = nil) -> Self {
		if let cache = self.loadCache() {
			if let time = cache["time"].double {
				if let pk = cache["pk"].string {
					if pk == primaryKey {
						let cachedTime = NSDate(timeIntervalSinceReferenceDate: time)
						if cachedTime.timeIntervalSinceNow > -maxAge {
							self.search.memcache = cache["results"].dictionaryObject
							self.search.memcacheKey = primaryKey
							println("use local data \(name)")
							done?(self.search.memcache!)
							return self
						}
					}
				}
			}
		}
		let group = dispatch_group_create()
		var cache: [String: AnyObject] = [:]
		println("start caching all \(name)")
		
		self.each(group) { object in
			cache[object[primaryKey].stringValue] = object.object
		}
		
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			self.search.memcache = cache
			self.search.memcacheKey = primaryKey
			println("\(self.name) ready")
			let json = JSON([
				"pk": primaryKey,
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": cache,
				"class": self.name])
			self.writeCache(json)
			done?(cache)
		}
		return self
	}
}
