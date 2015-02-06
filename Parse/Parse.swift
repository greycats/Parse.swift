//
//  Parse.swift
//
//  Created by Rex Sheng on 2/4/15.
//
//

import Foundation
import Alamofire
import SwiftyJSON

public let ParseErrorDomain = "co.interactivelabs.parse"

var manager_init_group: dispatch_group_t = {
	var group = dispatch_group_create()
	dispatch_group_enter(group)
	return group
	}()

var parseManager: Manager?

private let local_search_queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)

func parseRequest(method: Method, path: String, parameters: [String: AnyObject]?, closure: (JSON, NSError?) -> Void) {
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

public enum ParseData {
	case Date(NSDate)
	case Bytes(String)
	case Pointer(String, String)
	case Relation(String)
	case Unkown
	
	private static func formatter() -> NSDateFormatter {
		var dict = NSThread.currentThread().threadDictionary
		if let iso = dict["iso"] as? NSDateFormatter {
			return iso
		} else {
			let iso = NSDateFormatter()
			iso.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
			iso.timeZone = NSTimeZone(forSecondsFromGMT: 0)
			dict["iso"] = iso
			return iso
		}
	}
	
	func toJSON() -> [String: String]? {
		switch self {
		case .Date(let date):
			return ["__type": "Date", "iso": ParseData.formatter().stringFromDate(date)]
		case .Bytes(let base64):
			return ["__type": "Bytes", "base64": base64]
		case .Pointer(let className, let objectId):
			return ["__type": "Pointer", "className": className, "objectId": objectId]
		case .Relation(let className):
			return ["__type": "Relation", "className": className]
		default:
			return nil
		}
	}
	
	mutating func parse(dictionary: [String: String]) {
		let __type = dictionary["__type"]!
		switch __type {
		case "Date":
			self = .Date(ParseData.formatter().dateFromString(dictionary["iso"]!)!)
		case "Bytes":
			self = .Bytes(dictionary["base64"]!)
		case "Pointer":
			self = .Pointer(dictionary["className"]!, dictionary["objectId"]!)
		case "Relation":
			self = .Relation(dictionary["className"]!)
		default:
			self = .Unkown
		}
	}
}

public protocol ParseObject {
	init(json: JSON)
	var json: JSON? { get set }
	class var className: String { get }
}

public struct Search {
	var memcache: [JSON]? = nil
}

public class RestParse<T: ParseObject> {
	
	let name: String
	
	var search = Search()
	
	public init() {
		name = T.className
	}
	
	public func query(constraints: Constraint...) -> Query<T> {
		return Query<T>(self, constraints: constraints)
	}
	
	public func operation(objectId: String, operations: Operation...) -> Operations<T> {
		return Operations<T>(self, objectId: objectId, operations: operations)
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
	case In(key: String, collection: [AnyObject])
	case NotIn(key: String, collection: [AnyObject])
	case RelatedTo(key: String, className: String, objectId: String)
	
	func whereClause(inout param: [String: AnyObject]) {
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
		case .In(let key, let collection):
			param[key] = ["$in": collection]
		case .NotIn(let key, let collection):
			param[key] = ["$nin": collection]
		case .RelatedTo(let key, let className, let objectId):
			param["$relatedTo"] = ["object": ParseData.Pointer(className, objectId).toJSON()!, "key": key]
		}
	}
}

extension JSON {
	var date: NSDate? {
		return ParseData.formatter().dateFromString(self.stringValue)
	}
	var dateValue: NSDate {
		if let date = ParseData.formatter().dateFromString(self.stringValue) {
			return date
		} else {
			return NSDate()
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
			constraint.whereClause(&param)
		}
		return param
	}
}


public class Query<T: ParseObject> {
	
	var constraints: Constraints
	var parameters: [String: AnyObject] = [:]
	var path: String
	var object: RestParse<T>
	var order: String?
	var _limit: Int = 100
	var _skip: Int = 0
	
	var fetchesCount = false
	
	init(_ object: RestParse<T>, constraints: [Constraint] = []) {
		self.constraints = Constraints(className: object.name)
		self.object = object
		path = "/classes/\(object.name)"
		self.constraints.inner = constraints
	}
	
	private func convertParseType(object: AnyObject) -> AnyObject {
		if object is NSDate {
			return ParseData.Date(object as NSDate).toJSON()!
		}
		return object
	}
	
	public func constraint(constraint: Constraint) -> Self {
		constraints.append(constraint)
		return self
	}
	public func whereKey<T: ParseObject>(key: String, equalTo object: T) -> Self {
		let objectId = object.json!["objectId"].string!
		var to: AnyObject
		if key == "objectId" {
			to = objectId
		} else {
			to = ParseData.Pointer(object.dynamicType.className,  objectId).toJSON()!
		}
		constraints.append(.EqualTo(key: key, object: to))
		return self
	}
	
	public func whereKey(key: String, equalTo object: AnyObject) -> Self {
		let object: AnyObject = convertParseType(object)
		constraints.append(.EqualTo(key: key, object: object))
		return self
	}
	
	public func whereKey(key: String, greaterThan object: AnyObject) -> Self {
		let object: AnyObject = convertParseType(object)
		constraint(.GreaterThan(key: key, object: object))
		return self
	}
	
	public func whereKey(key: String, lessThan object: AnyObject) -> Self {
		let object: AnyObject = convertParseType(object)
		return constraint(.LessThan(key: key, object: object))
	}
	
	public func whereKey(key: String, containedIn: [AnyObject]) -> Self {
		return constraint(.In(key: key, collection: containedIn))
	}
	
	public func whereKey(key: String, notContainedIn: [AnyObject]) -> Self {
		return constraint(.NotIn(key: key, collection: notContainedIn))
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
		self._skip = skip
		parameters["skip"] = skip
		return self
	}
	
	public func order(order: String) -> Self {
		self.order = order
		parameters["order"] = order
		return self
	}
	
	public func limit(limit: Int) -> Self {
		_limit = limit
		parameters["limit"] = limit
		return self
	}
	
	var useLocal = true
	
	public func local(local: Bool) -> Self {
		useLocal = local
		return self
	}
	
	public func getRaw(closure: (JSON, NSError?) -> Void) {
		if useLocal {
			if self.object.search.searchLocal(self, closure: closure) {
				return
			}
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
//		let start = clock()
		getRaw { (json, error) in
			closure(json["count"].intValue, error)
//			let end = clock()
//			println("time cost \(end - start) unit")
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

public enum Operation {
	case AddUnique(String, [AnyObject])
	case Remove(String, [AnyObject])
	case Add(String, [AnyObject])
	case Increase(String, Int)
	case SetValue(String, AnyObject)
	case AddRelation(String, String, String)
	case RemoveRelation(String, String, String)
	
	func parse(inout param: [String: AnyObject]) {
		switch self {
		case .AddUnique(let key, let args):
			param[key] = ["__op": "AddUnique", "objects": args]
		case .Add(let key, let args):
			param[key] = ["__op": "Add", "objects": args]
		case .Remove(let key, let args):
			param[key] = ["__op": "Remove", "objects": args]
		case .Increase(let key, let args):
			param[key] = ["__op": "Increment", "amount": args]
		case .SetValue(let key, let args):
			param[key] = args
		case .AddRelation(let key, let className, let objectId):
			param[key] = ["__op": "AddRelation", "objects": [ParseData.Pointer(className, objectId).toJSON()!]]
		case .RemoveRelation(let key, let className, let objectId):
			param[key] = ["__op": "RemoveRelation", "objects": [ParseData.Pointer(className, objectId).toJSON()!]]
		}
	}
}

public class Operations<T: ParseObject> {
	
	var operations: [Operation]
	var path: String
	
	init(_ object: RestParse<T>, objectId: String, operations: [Operation] = []) {
		path = "/classes/\(object.name)/\(objectId)"
		self.operations = operations
	}
	
	public func operation(operation: Operation) {
		operations.append(operation)
	}
	
	public func addRelation<U: ParseObject>(key: String, to: U) -> Self {
		operation(.AddRelation(key, to.dynamicType.className, to.json!["objectId"].string!))
		return self
	}
	
	public func removeRelation<U: ParseObject>(key: String, to: U) -> Self {
		operation(.RemoveRelation(key, to.dynamicType.className, to.json!["objectId"].string!))
		return self
	}
	
	public func update(closure: (JSON, NSError?) -> Void) {
		var param: [String: AnyObject] = [:]
		for operation in operations {
			operation.parse(&param)
		}
		println("updating \(param) to \(path)")
		parseRequest(.PUT, path, param, closure)
	}
}

public func ||<T>(left: Query<T>, right: Query<T>) -> Query<T> {
	let query = Query<T>(left.object)
	query.constraints.append(.Or(left: left.constraints, right: right.constraints))
	return query
}

public func usersQuery() -> Query<User> {
	let query = RestParse<User>().query()
	query.path = "/users"
	return query
}

public struct User: ParseObject {
	
	public var json: JSON?
	
	public static var className: String { return "_User" }

	public init(json: JSON) {
		self.json = json
	}
	
	var username: String {
		return json!["username"].string!
	}
	
	func loginSession(block: (NSError?) -> Void) {
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			if var headers = parseManager!.session.configuration.HTTPAdditionalHeaders {
				headers["X-Parse-Session-Token"] = self.json!["sessionToken"].string
				parseManager!.session.configuration.HTTPAdditionalHeaders = headers
			}
			parseRequest(.GET, "/users/me", nil) { (json, error) in
				block(error)
			}
		}
	}
	
	public static func currentUser(block: (User?, NSError?) -> Void) {
		if let object: AnyObject = NSUserDefaults.standardUserDefaults().objectForKey("user") {
			let user = User(json: JSON(object))
			block(user, nil)
			println("returned user may not be valid server side")
			user.loginSession { error in
				if error != nil {
					println("logIn session \(user.username)")
					block(user, error)
				}
			}
		} else {
			block(nil, nil)
		}
	}
	
	public static func logIn(username: String, password: String, callback: (User?, NSError?) -> Void) {
		parseRequest(.GET, "/login", ["username": username, "password": password]) { (json, error) in
			if let error = error {
				return callback(nil, error)
			}
			NSUserDefaults.standardUserDefaults().setObject(json.object, forKey: "user")
			NSUserDefaults.standardUserDefaults().synchronize()
			println("logIn user \(json)")
			callback(User(json: json), error)
		}
	}
	
	public static func logOut() {
		NSUserDefaults.standardUserDefaults().removeObjectForKey("user")
		NSUserDefaults.standardUserDefaults().synchronize()
	}
	
	public static func signUp(username: String, password: String, extraInfo: [String: AnyObject]? = nil, callback: (User?, NSError?) -> Void) {
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
			println("signUp user \(u)")
			callback(User(json: u), error)
		}
	}
}

// local search
extension Search {
	
	func keys(matches: String, constraints: Constraints) -> [JSON] {
		var results: [JSON] = []
		if let cache = memcache {
			for json in cache {
				if constraints.match(json) {
					results.append(json[matches])
				}
			}
		}
		return results
	}
	
	func searchLocal<T: ParseObject>(query: Query<T>, closure: (JSON, NSError?) -> Void) -> Bool {
		if let cache = self.memcache {
			dispatch_barrier_async(local_search_queue) {
				query.constraints.replaceSubQueries()
				var results: [JSON] = []
				var count = 0
				for object in cache {
					if query.constraints.match(object) {
						count++
						if !query.fetchesCount {
							results.append(object)
							//TOOD
						}
					}
				}
				
				if let order = query.order {
					//TODO
					sort(&results, { (a, b) in
						return a[order] < b[order]
					})
					
					if results.count > query._limit {
						results = Array(results[0..<query._limit])
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
			let obj = json[key]
			for x in keys {
				if JSON(x) == obj {
					return true
				}
			}
			return false
		case .NotIn(let key, let keys):
			let obj = json[key]
			for x in keys {
				if JSON(x) == obj {
					return false
				}
			}
			return true
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
		case .RelatedTo(let key, let className, let objectId):
			return "related to \(className) \(objectId) under key \(key)"
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
				inner[index] = Constraint.In(key: key, collection: keys.map({$0.object}))
				replaced = true
			case .DoNotMatchQuery(let key, let dontMatchKey, let constraints, let search):
				let keys = search.keys(dontMatchKey, constraints: constraints)
				inner[index] = Constraint.NotIn(key: key, collection: keys.map({$0.object}))
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

extension RestParse {
	
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
		let key = "v2.\(name).json"
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
		let key = "v2.\(name).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			json.rawData()?.writeToFile(root.stringByAppendingPathComponent(key), atomically: true)
			println("\(name) data wrote to \(root.stringByAppendingPathComponent(key))")
		}
	}
	
	public func persistToLocal(maxAge: NSTimeInterval = 86400 * 7, done: (([JSON]) -> Void)? = nil) -> Self {
		if let cache = self.loadCache() {
			if let time = cache["time"].double {
				let cachedTime = NSDate(timeIntervalSinceReferenceDate: time)
				if cachedTime.timeIntervalSinceNow > -maxAge {
					self.search.memcache = cache["results"].dictionary?.values.array
					println("use local data \(name)")
					done?(self.search.memcache!)
					return self
				}
			}
		}
		let group = dispatch_group_create()
		var cache: [String: AnyObject] = [:]
		var jsons: [JSON] = []
		println("start caching all \(name)")
		
		self.each(group) { object in
			cache[object["objectId"].stringValue] = object.object
			jsons.append(object)
		}
		
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			self.search.memcache = jsons
			println("\(self.name) ready")
			let json = JSON([
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": cache,
				"class": self.name])
			self.writeCache(json)
			done?(jsons)
		}
		return self
	}
}
