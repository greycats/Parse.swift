//
//  Parse.swift
//
//  Created by Rex Sheng on 2/4/15.
//
//

import Foundation
import Alamofire
typealias Method = Alamofire.Method
import SwiftyJSON

public let ParseErrorDomain = "co.interactivelabs.parse"

public protocol ParseType {
	var json: JSON { get }
}

public protocol ParseObject: ParseType {
	init(json: JSON)
	class var className: String { get }
}

public class Parse<T: ParseObject> {
}

public struct Date {
	public let date: NSDate
}

public struct Bytes {
	public let bytes: NSData
}

public struct Pointer {
	public let className: String
	public let objectId: String
}

public struct GeoPoint {
	let latitude: Double
	let longitude: Double
}

public struct ACLRule {
	let name: String
	let write: Bool
	let read: Bool
}

public struct ACL {
	let rules: [ACLRule]
}

public enum Constraint {
	case GreaterThan(String, AnyObject)
	case LessThan(String, AnyObject)
	case EqualTo(String, AnyObject)
	case Exists(String, Bool)
	case MatchQuery(key: String, matchKey: String, inQuery: Constraints)
	case DoNotMatchQuery(key: String, dontMatchKey: String, inQuery: Constraints)
	case MatchRegex(String, NSRegularExpression)
	case Or(Constraints, Constraints)
	case In(String, [JSON])
	case NotIn(String, [JSON])
	case RelatedTo(String, Pointer)
}

public enum Operation {
	case AddUnique(String, [AnyObject])
	case Remove(String, [AnyObject])
	case Add(String, [AnyObject])
	case Increase(String, Int)
	case SetValue(String, AnyObject)
	case AddRelation(String, Pointer)
	case RemoveRelation(String, Pointer)
	case SetSecurity(User)
	case DeleteColumn(String)
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
}

public protocol ParseSystemObject: ParseObject {
	//TODO
}

protocol QueryComposer {
	func composeQuery(inout param: [String: AnyObject])
}

public class Query<T: ParseObject> {
	var constraints = Constraints(className: T.className)
	var path: String
	var order: String?
	var limit: Int?
	var includeKeys: String?
	var includeRelations: String?
	var skip: Int?
	var fetchesCount = false
	var useLocal = true
	
	public init(constraints: Constraint...) {
		path = "/classes/\(T.className)"
		self.constraints.inner.extend(constraints)
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
		let start = NSDate.timeIntervalSinceReferenceDate()
		getRaw { (json, error) in
			closure(json["count"].intValue, error)
			let end = NSDate.timeIntervalSinceReferenceDate()
			println("time cost \(end - start) unit")
		}
	}
}

public func ||<T>(left: Query<T>, right: Query<T>) -> Query<T> {
	return Query<T>(constraints: .Or(left.constraints, right.constraints))
}

public class ClassOperations<T: ParseObject> {
	var operations: [Operation]
	var path: String
	
	init(operations: [Operation] = []) {
		path = "/classes/\(T.className)"
		self.operations = operations
	}
	
	public func save(closure: (T?, NSError?) -> Void) {
		let param = _composeQuery(self)
		println("saving \(param) to \(path)")
		Client.request(.POST, path, param) { (json, error) in
			if let error = error {
				closure(nil, error)
				return
			}
			var object = JSON(param)
			object["createdAt"] = json["createdAt"]
			object["objectId"] = json["objectId"]
			LocalCache<T>.append(object)
			closure(T(json: object), nil)
		}
	}
}

public class ObjectOperations<T: ParseObject>: ClassOperations<T> {
	
	init(objectId: String, operations: [Operation] = []) {
		super.init(operations: operations)
		path = "/classes/\(T.className)/\(objectId)"
	}
	
	public func update(closure: (JSON, NSError?) -> Void) {
		var param: [String: AnyObject] = [:]
		for operation in operations {
			operation.composeQuery(&param)
		}
		println("updating \(param) to \(path)")
		Client.request(.PUT, path, param, closure)
	}
	
	public func delete(closure: (NSError?) -> Void) {
		Client.request(.DELETE, path, [:]) { (json, error) in
			closure(error)
		}
	}
}

public struct User: ParseObject {
	public static var className: String { return "_User" }
	public var json: JSON
	public var objectId: String
	
	public init(json: JSON) {
		self.json = json
		objectId = json["objectId"].string!
	}
	
	var username: String {
		return json["username"].string!
	}
}

public func usersQuery() -> Query<User> {
	let query = Query<User>()
	query.path = "/users"
	return query
}

public struct Client {
	static var manager_init_group: dispatch_group_t = {
		var group = dispatch_group_create()
		dispatch_group_enter(group)
		return group
		}()
	
	static var manager: Manager?
	
	static let local_search_queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
	
	static func request(method: Method, _ path: String, _ parameters: [String: AnyObject]?, _ closure: (JSON, NSError?) -> Void) {
		var pathString = "https://api.parse.com/1\(path)"
		var encoding: ParameterEncoding
		switch method {
		case .POST, .PUT:
			encoding = .JSON
		default:
			encoding = .URL
		}
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			self.manager!.request(method, pathString, parameters: parameters, encoding: encoding)
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
	
	static func loginSession(token: String, block: (NSError?) -> Void) {
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			if var headers = self.manager!.session.configuration.HTTPAdditionalHeaders {
				headers["X-Parse-Session-Token"] =  token
				self.manager!.session.configuration.HTTPAdditionalHeaders = headers
			}
			self.request(.GET, "/users/me", nil) { (json, error) in
				block(error)
			}
		}
	}
	
	public static func setup(#applicationId: String, restKey: String?, masterKey: String? = nil) {
		var configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
		var headers = ["X-Parse-Application-Id": applicationId]
		if let restKey = restKey {
			headers["X-Parse-REST-API-Key"] = restKey
		} else if let masterKey = masterKey {
			headers["X-Parse-Master-Key"] = masterKey
		}
		configuration.HTTPAdditionalHeaders = headers
		self.manager = Manager(configuration: configuration)
		dispatch_group_leave(manager_init_group)
	}
	
	public static func trackAppOpen() {
		request(.POST, "/events/AppOpened", [:]) { (json, error) in
			println("trackAppOpen error = \(error)")
		}
	}
}

// MARK: - Data Types

protocol _ParseType: ParseType {
	init?(_ json: JSON)
}

extension Date: _ParseType {
	
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
	
	init?(_ json: JSON) {
		if let type = json["__type"].string {
			if type == "Date" {
				date = Date.formatter().dateFromString(json["iso"].string!)!
				return
			}
		}
		return nil
	}
	
	public var json: JSON {
		return ["__type": "Date", "iso": Date.formatter().stringFromDate(date)]
	}
}

extension Bytes: _ParseType {
	init?(_ json: JSON) {
		if let type = json["__type"].string {
			if type == "Bytes" {
				bytes = NSData(base64EncodedString: json["base64"].string!, options: .allZeros)!
			}
		}
		return nil
	}
	
	public var json: JSON {
		return ["__type": "Bytes", "base64": bytes.base64EncodedStringWithOptions(.allZeros)]
	}
}

extension Pointer: _ParseType {
	
	init?(_ json: JSON) {
		if let type = json["__type"].string {
			if type == "Pointer" {
				self.className = json["className"].string!
				self.objectId = json["objectId"].string!
				return
			}
		}
		return nil
	}
	
	public init<T: ParseObject>(object: T) {
		className = T.className
		objectId = object.json["objectId"].string!
	}
	
	public var json: JSON {
		return ["__type": "Pointer", "className": className, "objectId": objectId]
	}
}

extension GeoPoint: _ParseType {
	
	init?(_ json: JSON) {
		if let type = json["__type"].string {
			if type == "GeoPoint" {
				self.latitude = json["latitude"].doubleValue
				self.longitude = json["longitude"].doubleValue
				return
			}
		}
		return nil
	}
	
	public var json: JSON {
		return ["__type": "GeoPoint", "latitude": latitude, "longitude": longitude]
	}
}

extension ACL: _ParseType {
	init?(_ json: JSON) {
		if let rules = json.dictionary {
			var _array: [ACLRule] = []
			for (key, value) in rules {
				_array.append(ACLRule(name: key, write: value["write"].bool ?? false, read: value["read"].bool ?? false))
			}
			self.rules = _array
			return
		}
		return nil
	}
	
	public var json: JSON {
		var result: [String: [String: Bool]] = [:]
		for acl in rules {
			var rule: [String: Bool] = [:]
			if acl.write {
				rule["write"] = true
			}
			if acl.read {
				rule["read"] = true
			}
			result[acl.name] = rule
		}
		return JSON(result)
	}
}

//MARK: - Parse API Composer

func _composeQuery(composer: QueryComposer) -> [String : AnyObject] {
	var param: [String: AnyObject] = [:]
	composer.composeQuery(&param)
	return param
}

extension Constraint: QueryComposer {
	func composeQuery(inout param: [String: AnyObject]) {
		switch self {
		case .GreaterThan(let key, let object):
			param[key] = ["$gt": object]
		case .LessThan(let key, let object):
			param[key] = ["$lt": object]
		case .EqualTo(let key, let object):
			param[key] = object as AnyObject
		case .MatchQuery(let key, let matchKey, let inQuery):
			param[key] = ["$select": ["key": matchKey, "query": ["className": inQuery.className, "where": _composeQuery(inQuery)]]]
		case .DoNotMatchQuery(let key, let dontMatchKey, let inQuery):
			param[key] = ["$dontSelect": ["key": dontMatchKey, "query": ["className": inQuery.className, "where": _composeQuery(inQuery)]]]
		case .MatchRegex(let key, let match):
			var options = ""
			if match.options & .CaseInsensitive == .CaseInsensitive {
				options += "i"
			}
			param[key] = ["$regex": match.pattern, "$options": options]
		case .Or(let left, let right):
			param["$or"] = [_composeQuery(left), _composeQuery(right)]
		case .In(let key, let collection):
			param[key] = ["$in": collection.map({$0.object})]
		case .NotIn(let key, let collection):
			param[key] = ["$nin": collection.map({$0.object})]
		case .RelatedTo(let key, let object):
			param["$relatedTo"] = ["object": object.json.object, "key": key]
		case .Exists(let key, let exists):
			param[key] = ["$exists": exists]
		}
	}
}

extension Constraints: QueryComposer {
	func composeQuery(inout param: [String : AnyObject]) {
		for constraint in inner {
			constraint.composeQuery(&param)
		}
	}
}

extension Query: QueryComposer {
	func composeQuery(inout param: [String : AnyObject]) {
		constraints.composeQuery(&param)
	}
}

extension Operation: QueryComposer {
	
	func composeQuery(inout param: [String: AnyObject]) {
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
		case .AddRelation(let key, let pointer):
			param[key] = ["__op": "AddRelation", "objects": [pointer.json.object]]
		case .RemoveRelation(let key, let pointer):
			param[key] = ["__op": "RemoveRelation", "objects": [pointer.json.object]]
		case .SetSecurity(let user):
			let acl = ACL(rules: [
				ACLRule(name: "*", write: false, read: true),
				ACLRule(name: user.objectId, write: true, read: true)])
			param["ACL"] = acl.json.object
		case .DeleteColumn(let key):
			param[key] = ["__op": "Delete"]
		}
	}
}

extension ClassOperations: QueryComposer {
	
	func composeQuery(inout param: [String : AnyObject]) {
		for operation in operations {
			operation.composeQuery(&param)
		}
	}
}

//MARK: - Shortcut Methods

extension Parse {
	
	public func query() -> Query<T> {
		return Query<T>()
	}
	
	public class func query(on: T.Type) -> Query<T> {
		return Query<T>()
	}
	
	public func operation(objectId: String, operations: Operation...) -> ObjectOperations<T> {
		return ObjectOperations<T>(objectId: objectId, operations: operations)
	}
	
	public class func operation(on: T.Type, objectId: String, operations: Operation...) -> ObjectOperations<T> {
		return ObjectOperations<T>(objectId: objectId, operations: operations)
	}
	
	public class func operation(on: T, operations: Operation...) -> ObjectOperations<T> {
		return ObjectOperations<T>(objectId: on.json["objectId"].string!, operations: operations)
	}
	
	public func operation(operations: Operation...) -> ClassOperations<T> {
		return ClassOperations<T>(operations: operations)
	}
	
	public class func operation(on: T.Type, operations: Operation...) -> ClassOperations<T> {
		return ClassOperations<T>(operations: operations)
	}
}

public func parseFunction(name: String, parameters: [String: AnyObject], done: (JSON, NSError?) -> Void) {
	Client.request(.POST, "/function/\(name)", parameters, done)
}

extension Query {
	public func constraint(constraint: Constraint) -> Self {
		constraints.append(constraint)
		return self
	}
	public func whereKey(key: String, equalTo string: String) -> Self {
		return constraint(.EqualTo(key, string))
	}
	
	public func whereKey(key: String, equalTo number: Int) -> Self {
		return constraint(.EqualTo(key, number))
	}
	
	public func whereKey(key: String, equalTo date: NSDate) -> Self {
		return whereKey(key, equalTo: Date(date: date))
	}
	
	public func whereKey(key: String, equalTo data: Date) -> Self {
		return constraint(.EqualTo(key, data.json.object))
	}
	
	public func whereKey<U: ParseObject>(key: String, equalTo object: U) -> Self {
		let objectId = object.json["objectId"].string!
		var to: AnyObject
		if key == "objectId" {
			to = objectId
		} else {
			to = Pointer(className: object.dynamicType.className, objectId: objectId).json.object
		}
		return constraint(.EqualTo(key, to))
	}
	
	public func whereKey(key: String, greaterThan time: NSDate) -> Self {
		return whereKey(key, greaterThan: Date(date: time))
	}
	
	public func whereKey(key: String, greaterThan data: Date) -> Self {
		return constraint(.GreaterThan(key, data.json.object))
	}
	
	public func whereKey(key: String, greaterThan object: AnyObject) -> Self {
		return constraint(.GreaterThan(key, object))
	}
	
	public func whereKey(key: String, lessThan time: NSDate) -> Self {
		return whereKey(key, greaterThan: Date(date: time))
	}
	
	public func whereKey<U: ParseType>(key: String, lessThan data: U) -> Self {
		return constraint(.GreaterThan(key, data.json.object))
	}
	
	public func whereKey(key: String, lessThan object: AnyObject) -> Self {
		return constraint(.LessThan(key, object))
	}
	
	public func whereKey(key: String, containedIn: [AnyObject]) -> Self {
		return constraint(.In(key, containedIn.map({JSON($0)})))
	}
	
	public func whereKey(key: String, notContainedIn: [AnyObject]) -> Self {
		return constraint(.NotIn(key, notContainedIn.map({JSON($0)})))
	}
	
	public func whereKey<U: ParseObject>(key: String, matchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.MatchQuery(key: key, matchKey: matchKey, inQuery: inQuery.constraints))
	}
	
	public func whereKey<U: ParseObject>(key: String, dontMatchKey: String, inQuery: Query<U>) -> Self {
		return constraint(.DoNotMatchQuery(key: key, dontMatchKey: dontMatchKey, inQuery: inQuery.constraints))
	}
	
	public func whereKey(key: String, match: NSRegularExpression) -> Self {
		return constraint(.MatchRegex(key, match))
	}
	
	public func whereKey(key: String, exists: Bool) -> Self {
		return constraint(.Exists(key, exists))
	}
	
	public func relatedTo<U: ParseObject>(object: U, key: String) -> Self {
		return constraint(.RelatedTo(key, Pointer(object: object)))
	}
	
	public func relatedTo(className: String, objectId: String, key: String) -> Self {
		return constraint(.RelatedTo(key, Pointer(className: className,  objectId: objectId)))
	}
	
	public func keys(exp: String) -> Self {
		includeKeys = exp
		return self
	}
	
	public func include(exp: String) -> Self {
		includeRelations = exp
		return self
	}
	
	public func skip(skip: Int) -> Self {
		self.skip = skip
		return self
	}
	
	public func order(order: String) -> Self {
		self.order = order
		return self
	}
	
	public func limit(limit: Int) -> Self {
		self.limit = limit
		return self
	}
	
	public func local(local: Bool) -> Self {
		useLocal = local
		return self
	}
	
	public func get(objectId: String, closure: (T?, NSError?) -> Void) {
		self.whereKey("objectId", equalTo: objectId).first(closure)
	}
	
	public func first(closure: (T?, NSError?) -> Void) {
		limit(1)
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

extension ClassOperations {
	public func operation(operation: Operation) -> Self {
		operations.append(operation)
		return self
	}
	
	public func set(key: String, value: Int) -> Self {
		return operation(.SetValue(key, value))
	}
	
	public func set(key: String, value: String) -> Self {
		return operation(.SetValue(key, value))
	}
	
	public func set<U: ParseObject>(key: String, value: U) -> Self {
		return operation(.SetValue(key, Pointer(object: value).json.object))
	}
	
	public func setSecurity(readwrite: User) -> Self {
		return operation(.SetSecurity(readwrite))
	}
	
	public func addRelation<U: ParseObject>(key: String, to: U) -> Self {
		operation(.AddRelation(key, Pointer(object: to)))
		return self
	}
}

extension ObjectOperations {
	
	public func addUnique(key: String, object: AnyObject) -> Self {
		return operation(.AddUnique(key, [object]))
	}
	
	public func add(key: String, object: AnyObject) -> Self {
		return operation(.Add(key, [object]))
	}
	
	public func remove(key: String, object: AnyObject) -> Self {
		return operation(.Remove(key, [object]))
	}
	
	public func addUnique(key: String, objects: [AnyObject]) -> Self {
		return operation(.AddUnique(key, objects))
	}
	
	public func add(key: String, objects: [AnyObject]) -> Self {
		return operation(.Add(key, objects))
	}
	
	public func remove(key: String, objects: [AnyObject]) -> Self {
		return operation(.Remove(key, objects))
	}
	
	public func increase(key: String, amount: Int) -> Self {
		return operation(.Increase(key, amount))
	}
	
	public func removeRelation<U: ParseObject>(key: String, to: U) -> Self {
		operation(.RemoveRelation(key, Pointer(object: to)))
		return self
	}
}

public protocol UserFunctions {
	class func currentUser(block: (User?, NSError?) -> Void)
	class func logIn(username: String, password: String, callback: (User?, NSError?) -> Void)
	class func logOut()
	class func signUp(username: String, password: String, extraInfo: [String: AnyObject]?, callback: (User?, NSError?) -> Void)
}

extension User: ParseSystemObject, UserFunctions {
	public static func currentUser(block: (User?, NSError?) -> Void) {
		if let object: AnyObject = NSUserDefaults.standardUserDefaults().objectForKey("user") {
			let user = User(json: JSON(object))
			block(user, nil)
			println("returned user may not be valid server side")
			Client.loginSession(user.json["sessionToken"].string!) { error in
				if let error = error {
					println("session login failed \(user.username) \(error)")
					block(user, error)
				}
			}
		} else {
			block(nil, nil)
		}
	}
	
	public static func logIn(username: String, password: String, callback: (User?, NSError?) -> Void) {
		Client.request(.GET, "/login", ["username": username, "password": password]) { (json, error) in
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
		Client.request(.POST, "/users", param) { (json, error) in
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

//MARK: - Local Search & Cache

struct LocalPersistence {
	static var classCache: [String: [JSON]] = [:]
	static var relationCache: [String: [JSON]] = [:]
}

protocol LocalMatch {
	func match(json: JSON) -> Bool
}

extension Query {
	func searchLocal(closure: (JSON, NSError?) -> Void) -> Bool {
		if !useLocal || !constraints.allowsLocalSearch() {
			return false
		}
		if let cache = LocalPersistence.classCache[T.className] {
			dispatch_barrier_async(Client.local_search_queue) {
				self.constraints.replaceSubQueries { (key, constraints) in
					if let innerCache = LocalPersistence.classCache[constraints.className] {
						return innerCache.filter { constraints.match($0) }.map { $0[key] }
					} else {
						return []
					}
				}
				var results: [JSON] = []
				var count = 0
				for object in cache {
					if self.constraints.match(object) {
						count++
						if !self.fetchesCount {
							results.append(object)
							//TOOD selected Keys?
						}
					}
				}
				
				self.ordered(&results)
				
				var limit = 100
				if let _limit = self.limit {
					limit = _limit
				}
				if results.count > limit {
					results = Array(results[0..<limit])
				}
				
				dispatch_async(dispatch_get_main_queue()) {
					var result: [String: AnyObject] = [:]
					if self.fetchesCount {
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

extension Query {
	func ordered(inout results: [JSON]) {
		if var order = self.order {
			let orders = split(order) { $0 == "," }
			var comparators: [(JSON, JSON) -> NSComparisonResult] = []
			for order in orders {
				let desc = order.hasPrefix("-")
				if desc {
					let order = order.substringFromIndex(order.startIndex.successor())
					comparators.append({ $0[order].compare($1[order]) })
				} else {
					comparators.append({ $1[order].compare($0[order]) })
				}
			}
			sort(&results) {
				for comparator in comparators {
					switch comparator($0, $1) {
					case .OrderedSame:
						continue
					case .OrderedAscending:
						return false
					case .OrderedDescending:
						return true
					}
				}
				return false
			}
		}
	}
}

extension JSON {
	func compare(a: JSON) -> NSComparisonResult {
		if self == a {
			return .OrderedSame
		}
		return self < a ? .OrderedAscending : .OrderedDescending
	}
}

extension Constraint: LocalMatch {
	
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
		case .Exists(let key, let exists):
			let isNil = json[key] == nil
			if exists {
				return !isNil
			} else {
				return isNil
			}
		default:
			return false
		}
	}
}

extension Constraints: LocalMatch {
	
	func allowsLocalSearch() -> Bool {
		for constraint in inner {
			switch constraint {
			case .EqualTo(let key, let to):
				if let data = to as? [String: AnyObject] {
					if let _type = data["__type"] as? String {
						if _type == "Pointer" {
							return false
						}
					}
				}
			default:
				continue
			}
		}
		return true
	}
	
	mutating func replaceSubQueries(keys: (String, Constraints) -> [JSON]) {
		var replaced = false
		for (index, constraint) in enumerate(inner) {
			switch constraint {
			case .MatchQuery(let key, let matchKey, let constraints):
				inner[index] = Constraint.In(key, keys(matchKey, constraints))
				replaced = true
			case .DoNotMatchQuery(let key, let dontMatchKey, let constraints):
				inner[index] = Constraint.NotIn(key, keys(dontMatchKey, constraints))
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

extension Query {
	func paging(group: dispatch_group_t, skip: Int = 0, block: (JSON) -> Void) {
		dispatch_group_enter(group)
		self.local(false).limit(1000).skip(skip).getRaw { (objects, error) -> Void in
			if objects["results"].count == 1000 {
				self.paging(group, skip: skip + 1000, block: block)
			}
			block(objects)
			dispatch_group_leave(group)
		}
	}
	
	public func each(group: dispatch_group_t, block: (JSON) -> Void) {
		self.paging(group, skip: 0) { objects in
			for object in objects["results"].arrayValue {
				block(object)
			}
		}
	}
	
	public func each(group: dispatch_group_t, concurrent: Int, block: (JSON, () -> ()) -> Void) {
		let semophore = dispatch_semaphore_create(concurrent)
		let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
		self.each(group) { (json) in
			dispatch_group_enter(group)
			dispatch_barrier_async(queue) {
				dispatch_semaphore_wait(semophore, DISPATCH_TIME_FOREVER)
				block(json) {
					dispatch_semaphore_signal(semophore)
					dispatch_group_leave(group)
				}
			}
		}
	}
	
	func eachPage(group: dispatch_group_t, block: (JSON) -> Void) {
		self.paging(group, skip: 0) { objects in
			block(objects)
		}
	}
}

struct LocalCache<T: ParseObject> {
	
	static func loadCache() -> JSON? {
		let key = "v2.\(T.className).json"
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
	
	static func writeCache(json: JSON) {
		let key = "v2.\(T.className).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			json.rawData()?.writeToFile(root.stringByAppendingPathComponent(key), atomically: true)
			println("\(T.className) data wrote to \(root.stringByAppendingPathComponent(key))")
		}
	}
	
	static func append(dom: JSON) {
		if let cache = self.loadCache() {
			var results = cache["results"].dictionaryObject!
			results[dom["objectId"].string!] = dom.object
			LocalPersistence.classCache[T.className]?.append(dom)
			let json = JSON([
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": results,
				"class": T.className])
			self.writeCache(json)
		}
	}
	
	static func persistent(maxAge: NSTimeInterval, done: ([JSON] -> Void)?) {
		if let cache = self.loadCache() {
			if let time = cache["time"].double {
				let cachedTime = NSDate(timeIntervalSinceReferenceDate: time)
				if cachedTime.timeIntervalSinceNow > -maxAge {
					let cache = cache["results"].dictionary?.values.array
					if cache?.count > 0 {
						LocalPersistence.classCache[T.className] = cache
						println("use local data \(T.className) count=\(cache!.count)")
						done?(cache!)
						return
					}
				}
			}
		}
		let group = dispatch_group_create()
		var cache: [String: AnyObject] = [:]
		var jsons: [JSON] = []
		println("start caching all \(T.className)")
		
		Query<T>().each(group) { object in
			cache[object["objectId"].stringValue] = object.object
			jsons.append(object)
		}
		
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			LocalPersistence.classCache[T.className] = jsons
			println("\(T.className) ready")
			let json = JSON([
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": cache,
				"class": T.className])
			self.writeCache(json)
			done?(jsons)
		}
	}
}

//MARK: - Dispatcher

extension Query {
	func getRaw(closure: (JSON, NSError?) -> Void) {
		if self.searchLocal(closure) { return }
		
		var parameters: [String: AnyObject] = [:]
		var _where: [String: AnyObject] = [:]
		self.composeQuery(&_where)
		if _where.count > 0 {
			parameters["where"] = JSON(_where).rawString()
		}
		if let keys = includeKeys {
			parameters["keys"] = keys
		}
		if let relations = includeRelations {
			parameters["include"] = relations
		}
		if let limit = limit {
			parameters["limit"] = limit
		}
		if let skip = skip {
			parameters["skip"] = skip
		}
		if let order = order {
			parameters["order"] = order
		}
		if fetchesCount {
			parameters["count"] = 1
		}
		println("sending \(parameters) to \(path)")
		Client.request(.GET, path, parameters, closure)
	}
}

extension Parse {
	public func persistent(maxAge: NSTimeInterval, done: ([JSON] -> Void)? = nil) -> Self {
		LocalCache<T>.persistent(maxAge, done: done)
		return self
	}
}

//MARK: - Printable

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
		case .MatchQuery(let key, let matchKey, let inQuery):
			return "\(key) matches \(matchKey) from \(inQuery.className) where \(_composeQuery(inQuery))"
		case .DoNotMatchQuery(let key, let dontMatchKey, let inQuery):
			return "\(key) doesn't match \(dontMatchKey) from \(inQuery.className) where \(_composeQuery(inQuery))"
		case .RelatedTo(let key, let object):
			return "related to \(object) under key \(key)"
		case .Exists(let key, let exists):
			return "\(key) exists = \(exists)"
		}
	}
}

extension Constraints: Printable {
	public var description: String {
		return "\(inner)"
	}
}
