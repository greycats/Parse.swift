//
//  Parse.swift
//
//  Created by Rex Sheng on 2/4/15.
//
//

import Alamofire
typealias Method = Alamofire.Method

public let ParseErrorDomain = "co.interactivelabs.parse"

public protocol ParseType {
	var json: AnyObject { get }
}

public protocol ParseObject {
	init(json: Data)
	var json: Data { get }
	static var className: String { get }
}

public class Parse<T: ParseObject> {
}

public struct Value {
	enum Type {
		case Number
		case String
		case Null
	}
	let type: Type
	public let object: RawValue
}

public struct Date {
	public let date: NSDate
}

public struct Bytes {
	public let bytes: NSData
}

public struct File {
	public let fileName: String
	public let urlString: String
	
	public init(fileName: String) {
		self.fileName = fileName
		self.urlString = ""
	}
}

public struct Pointer {
	public let className: String
	public let objectId: String
	public let connections: [String: Pointer]?
	
	public init(className: String, objectId: String, connections: [String: Pointer]? = nil) {
		self.className = className
		self.objectId = objectId
		self.connections = connections
	}
}

public struct GeoPoint {
	public let latitude: Double
	public let longitude: Double
}

public struct ACLRule {
	public let name: String
	public let write: Bool
	public let read: Bool
}

public struct ACL {
	public let rules: [ACLRule]
}

public struct Data {
	let raw: [String: AnyObject]
	private var pending: [String: ParseType]?
	public init(_ raw: [String: AnyObject]) {
		self.raw = raw
	}
}

public enum Constraint {
	case GreaterThan(String, ParseType)
	case LessThan(String, ParseType)
	case EqualTo(String, ParseType)
	case Exists(String, Bool)
	case MatchQuery(key: String, matchKey: String, inQuery: Constraints)
	case DoNotMatchQuery(key: String, dontMatchKey: String, inQuery: Constraints)
	case MatchRegex(String, NSRegularExpression)
	case Or(Constraints, Constraints)
	case In(String, [Value])
	case NotIn(String, [Value])
	case RelatedTo(String, Pointer)
}

public enum Operation {
	case AddUnique(String, [AnyObject])
	case Remove(String, [AnyObject])
	case Add(String, [AnyObject])
	case Increase(String, Int)
	case SetValue(String, ParseType)
	case AddRelation(String, Pointer)
	case RemoveRelation(String, Pointer)
	case SetSecurity(String)
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

protocol QueryComposer {
	func composeQuery(inout param: [String: AnyObject])
}

public class _Query {
	var constraints: Constraints
	var order: String?
	var limit: Int?
	var includeKeys: String?
	var includeRelations: String?
	var skip: Int?
	var fetchesCount = false
	
	init(className: String, constraints: Constraint...) {
		self.constraints = Constraints(className: className)
		self.constraints.inner.extend(constraints)
	}
	
	func getRaw(closure: ([String: AnyObject]?, NSError?) -> Void) {
		var parameters: [String: AnyObject] = [:]
		var _where: [String: AnyObject] = [:]
		self.composeQuery(&_where)
		if _where.count > 0 {
			if let data = NSJSONSerialization.dataWithJSONObject(_where, options: nil, error: nil) {
				parameters["where"] = NSString(data: data, encoding: NSUTF8StringEncoding)
			}
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
		let _path = path(constraints.className)
		println("sending \(parameters) to \(_path)")
		Client.request(.GET, _path, parameters, closure)
	}
	
	func list(closure: ([Data], NSError?) -> Void) {
		getRaw { (json, error) in
			if let json = json {
				if let array = json["results"] as? [[String: AnyObject]] {
					closure(array.map { Data($0) }, error)
					return
				}
			}
			closure([], error)
		}
	}
	
	func count(closure: (Int, NSError?) -> Void) {
		fetchesCount = true
		limit(1)
		getRaw { (json, error) in
			if let json = json {
				if let count = json["count"] as? Int {
					closure(count, error)
					return
				}
			}
			closure(0, error)
		}
	}
}

public class Query<T: ParseObject>: _Query {
	
	var useLocal = true
	
	public init(constraints: Constraint...) {
		super.init(className: T.className)
		self.constraints.inner.extend(constraints)
	}
	
	override func getRaw(closure: ([String : AnyObject]?, NSError?) -> Void) {
		if self.searchLocal(closure) { return }
		super.getRaw(closure)
	}
	
	public func get(closure: ([T], NSError?) -> Void) {
		list { (data, error) -> Void in
			closure(data.map { T(json: $0) }, error)
		}
	}
}

public func ||<T>(left: Query<T>, right: Query<T>) -> Query<T> {
	return Query<T>(constraints: .Or(left.constraints, right.constraints))
}

public class _Operations<T: ParseObject> {
	var operations: [Operation]
	
	init(operations: [Operation]) {
		self.operations = operations
	}
}

public class ClassOperations<T: ParseObject>: _Operations<T> {
	public init() {
		super.init(operations: [])
	}
}

public class ObjectOperations<T: ParseObject>: _Operations<T> {
	let objectId: String
	
	public init(_ objectId: String, operations: [Operation]) {
		self.objectId = objectId
		super.init(operations: operations)
	}
}

// MARK: - Data Types

protocol _ParseType: ParseType {
	typealias RawValue
	init?(_ json: RawValue)
}

struct AnyWrapper: _ParseType {
	typealias RawValue = AnyObject
	var json: RawValue
	init(_ json: RawValue) {
		self.json = json
	}
}

extension Date: _ParseType {
	typealias RawValue = [String: String]
	
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
	
	init(iso: String) {
		date = Date.formatter().dateFromString(iso)!
	}
	
	init?(_ json: RawValue) {
		if json["__type"] == "Date" {
			date = Date.formatter().dateFromString(json["iso"]!)!
			return
		}
		return nil
	}
	
	public var json: AnyObject {
		return ["__type": "Date", "iso": Date.formatter().stringFromDate(date)]
	}
}

extension Bytes: _ParseType {
	public typealias RawValue = [String: String]
	
	init?(_ json: RawValue) {
		if json["__type"] == "Bytes" {
			bytes = NSData(base64EncodedString: json["base64"]!, options: .allZeros)!
			return
		}
		return nil
	}
	
	public var json: AnyObject {
		return ["__type": "Bytes", "base64": bytes.base64EncodedStringWithOptions(.allZeros)]
	}
}

extension File: _ParseType {
	public typealias RawValue = [String: String]
	
	init?(_ json: RawValue) {
		if json["__type"] == "File" {
			self.fileName = json["name"]! as String
			self.urlString = json["url"]! as String
			return
		}
		return nil
	}
	
	public var json : AnyObject {
		return ["__type": "File", "name": fileName]
	}
}

extension Pointer: _ParseType {
	public typealias RawValue = [String: String]
	
	init?(_ json: RawValue) {
		if json["__type"] == "Pointer" {
			self.className = json["className"]! as String
			self.objectId = json["objectId"]! as String
			self.connections = nil
			return
		}
		return nil
	}
	
	public init<T: ParseObject>(object: T) {
		var connections: [String: Pointer] = [:]
		for k in object.json.keys {
			if let p = object.json.pointer(k) {
				connections[k] = p
			}
		}
		className = T.className
		objectId = object.json.objectId
		self.connections = connections
	}
	
	public init(className: String, data: Data) {
		var connections: [String: Pointer] = [:]
		for k in data.keys {
			if let p = data.pointer(k) {
				connections[k] = p
			}
		}
		self.className = className
		objectId = data.objectId
		self.connections = connections
	}
	
	public var json: AnyObject {
		return ["__type": "Pointer", "className": className, "objectId": objectId]
	}
}

extension GeoPoint: _ParseType {
	public typealias RawValue = [String: NSObject]
	
	init?(_ json: RawValue) {
		if let type = json["__type"] as? String {
			if type == "GeoPoint" {
				self.latitude = json["latitude"]! as! Double
				self.longitude = json["longitude"]! as! Double
				return
			}
		}
		return nil
	}
	
	public var json: AnyObject {
		return ["__type": "GeoPoint", "latitude": latitude, "longitude": longitude]
	}
}

extension ACL: _ParseType {
	public typealias RawValue = [String: [String: Bool]]
	
	init?(_ json: RawValue) {
		var _array: [ACLRule] = []
		for (key, value) in json {
			var write = false
			var read = false
			if let w = value["write"] {
				write = w
			}
			if let r = value["read"] {
				read = r
			}
			_array.append(ACLRule(name: key, write: write, read: read))
		}
		self.rules = _array
	}
	
	public var json: AnyObject {
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
		return result
	}
}

extension Value: _ParseType {
	public typealias RawValue = AnyObject?
	
	init(_ json: RawValue) {
		switch json {
		case let string as String:
			type = .String
			object = json
		case let number as Double:
			type = .Number
			object = json
		default:
			type = .Null
			object = nil
		}
	}
	
	var int: Int? {
		return object as? Int
	}
	
	var double: Double {
		return object as! Double
	}
	
	var string: String? {
		return object as? String
	}
	
	var bool: Bool {
		return object as! Bool
	}
	
	public var json: AnyObject {
		if let o: AnyObject = object {
			return o
		} else {
			return NSNull()
		}
	}
}

extension Data {
	func check<V, T: _ParseType>(value: V?, _ t: T.Type) -> T? {
		if let value = value as? T.RawValue {
			return T(value)
		}
		return nil
	}
	
	public func pointer(key: String) -> Pointer? {
		return check(raw[key], Pointer.self)
	}
	
	public func file(key: String) -> File? {
		return check(raw[key], File.self)
	}

	public var keys: [String] {
		return raw.keys.array
	}
	
	public func date(key: String) -> Date? {
		if key == "createdAt" || key == "updatedAt" {
			if let iso = raw[key] as? String {
				return Date(iso: iso)
			}
		}
		if let date = check(raw[key], Date.self) {
			return date
		}
		return nil
	}
	
	public func bytes(key: String) -> Bytes? {
		return check(raw[key], Bytes.self)
	}
	
	public func geoPoint(key: String) -> GeoPoint? {
		return check(raw[key], GeoPoint.self)
	}
	
	public func value(key: String) -> Value {
		return Value(raw[key])
	}
	
	public var security: ACL? {
		return check(raw["ACL"], ACL.self)
	}
	
	public var objectId: String {
		return value("objectId").string!
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
			param[key] = ["$gt": object.json]
		case .LessThan(let key, let object):
			param[key] = ["$lt": object.json]
		case .EqualTo(let key, let object):
			param[key] = object.json
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
			param[key] = ["$in": collection.map({$0.json})]
		case .NotIn(let key, let collection):
			param[key] = ["$nin": collection.map({$0.json})]
		case .RelatedTo(let key, let object):
			param["$relatedTo"] = ["object": object.json, "key": key]
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

extension _Query: QueryComposer {
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
			param[key] = args.json
		case .AddRelation(let key, let pointer):
			param[key] = ["__op": "AddRelation", "objects": [pointer.json]]
		case .RemoveRelation(let key, let pointer):
			param[key] = ["__op": "RemoveRelation", "objects": [pointer.json]]
		case .SetSecurity(let objectId):
			let acl = ACL(rules: [
				ACLRule(name: "*", write: false, read: true),
				ACLRule(name: objectId, write: true, read: true)])
			param["ACL"] = acl.json
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
	public class func operation(objectId: String) -> ObjectOperations<T> {
		return ObjectOperations<T>(objectId, operations: [])
	}
	
	public class func operation(#on: T) -> ObjectOperations<T> {
		let operations = ObjectOperations<T>(on.json.objectId, operations: [])
		if let pending = on.json.pending {
			for (key, value) in pending {
				switch value {
				case let v as Value:
					operations.set(key, value: v)
				case let p as Pointer:
					operations.set(key, value: p)
				case let d as Date:
					operations.set(key, value: d)
				case let f as File:
					operations.set(key, value: f)
				default:
					break
				}
			}
		}
		return operations
	}
	
	public class func operation() -> ClassOperations<T> {
		return ClassOperations<T>()
	}
	
	public class func get(objectId: String, closure: (T) -> Void) {
		ObjectCache.get(objectId, closure: closure)
	}
	
}

@objc public protocol ComparableKeyType: NSObjectProtocol {}
extension NSDate: ComparableKeyType {}
extension NSNumber: ComparableKeyType {}
extension NSString: ComparableKeyType {}

extension Pointer {
	subscript(key: String) -> Pointer {
		return connections![key]!
	}
}

extension _Query {
	public func constraint(constraint: Constraint) -> Self {
		constraints.append(constraint)
		return self
	}
	
	public func whereKey<U: ParseType>(key: String, equalTo object: U) -> Self {
		if key == "objectId" && object is Pointer {
			return constraint(.EqualTo(key, Value((object as! Pointer).objectId)))
		} else {
			return constraint(.EqualTo(key, object))
		}
	}
	
	public func whereKey(key: String, equalTo object: ComparableKeyType) -> Self {
		if let date = object as? NSDate {
			return constraint(.EqualTo(key, Date(date: date)))
		}
		return constraint(.EqualTo(key, Value(object)))
	}
	
	public func whereKey<U: ParseObject>(key: String, equalTo object: U) -> Self {
		let objectId = object.json.objectId
		if key == "objectId" {
			return constraint(.EqualTo(key, Value(objectId)))
		} else {
			return constraint(.EqualTo(key, Pointer(object: object)))
		}
	}
	
	public func whereKey<U: ParseType>(key: String, greaterThan object: U) -> Self {
		return constraint(.GreaterThan(key, object))
	}
	
	public func whereKey(key: String, greaterThan object: ComparableKeyType) -> Self {
		if let date = object as? NSDate {
			return constraint(.GreaterThan(key, Date(date: date)))
		}
		return constraint(.GreaterThan(key, Value(object)))
	}
	
	public func whereKey<U: ParseType>(key: String, lessThan object: U) -> Self {
		return constraint(.LessThan(key, object))
	}
	
	public func whereKey(key: String, lessThan object: ComparableKeyType) -> Self {
		if let date = object as? NSDate {
			return constraint(.LessThan(key, Date(date: date)))
		}
		return constraint(.LessThan(key, Value(object)))
	}
	
	public func whereKey(key: String, containedIn: [Value]) -> Self {
		return constraint(.In(key, containedIn))
	}
	
	public func whereKey(key: String, containedIn: [String]) -> Self {
		let values = containedIn.map({ Value($0) })
		return constraint(.In(key, values))
	}
	
	public func whereKey(key: String, containedIn: [Int]) -> Self {
		let values = containedIn.map({ Value($0) })
		return constraint(.In(key, values))
	}
	
	public func whereKey(key: String, notContainedIn: [Value]) -> Self {
		return constraint(.NotIn(key, notContainedIn))
	}
	
	public func whereKey(key: String, notContainedIn: [String]) -> Self {
		let values = notContainedIn.map({ Value($0) })
		return constraint(.NotIn(key, values))
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
	
	public func relatedTo(pointer: Pointer, key: String) -> Self {
		return constraint(.RelatedTo(key, pointer))
	}
	
	public func relatedTo(className: String, objectId: String, key: String) -> Self {
		return relatedTo(Pointer(className: className,  objectId: objectId), key: key)
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
}

extension Query {
	public func local(local: Bool) -> Self {
		useLocal = local
		return self
	}
	
	public func first(closure: (T?, NSError?) -> Void) {
		limit(1)
		get { (ts, error) in
			closure(ts.first, error)
		}
	}
}

extension _Operations {
	public func operation(operation: Operation) -> Self {
		operations.append(operation)
		return self
	}
	
	public func set(key: String, value: [AnyObject]) -> Self {
		return operation(.SetValue(key, AnyWrapper(value)))
	}
	
	public func set(key: String, value: ComparableKeyType) -> Self {
		if let date = value as? NSDate {
			return set(key, value: Date(date: date))
		}
		return set(key, value: Value(value))
	}
	
	public func set<U: ParseObject>(key: String, value: U) -> Self {
		return operation(.SetValue(key, Pointer(object: value)))
	}
	
	public func set<U: ParseType>(key: String, value: U) -> Self {
		return operation(.SetValue(key, value))
	}
	
	public func addRelation<U: ParseObject>(key: String, to: U) -> Self {
		return operation(.AddRelation(key, Pointer(object: to)))
	}
	
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
		return operation(.RemoveRelation(key, Pointer(object: to)))
	}
}

//MARK: - Comparable

extension Value: Comparable {}

public func ==(lhs: Value, rhs: Value) -> Bool {
	switch (lhs.type, rhs.type) {
	case (.Number, .Number):
		return (lhs.object as! Double) == (rhs.object as! Double)
	case (.String, .String):
		return (lhs.object as! String) == (rhs.object as! String)
	case (.Null, .Null):
		return true
	default:
		return false
	}
}

public func <(lhs: Value, rhs: Value) -> Bool {
	switch (lhs.type, rhs.type) {
	case (.Number, .Number):
		return (lhs.object as! Double) < (rhs.object as! Double)
	case (.String, .String):
		return (lhs.object as! String) < (rhs.object as! String)
	case (.Null, .Null):
		return true
	default:
		return false
	}
}

extension Date: Comparable {}

public func ==(lhs: Date, rhs: Date) -> Bool {
	return lhs.date.timeIntervalSinceReferenceDate == rhs.date.timeIntervalSinceReferenceDate
}

public func <(lhs: Date, rhs: Date) -> Bool {
	return lhs.date.timeIntervalSinceReferenceDate < rhs.date.timeIntervalSinceReferenceDate
}

extension Data {
	subscript(key: String) -> ParseType {
		get {
			if let d = date(key) {
				return d
			}
			return value(key)
		}
		set {
			var _pending = pending ?? [:]
			_pending[key] = newValue
			pending = _pending
		}
	}
}

extension Data: Equatable {
}

public func ==(lhs: Data, rhs: Data) -> Bool {
	return lhs.objectId == rhs.objectId
}

public func ==<T: ParseObject>(lhs: T, rhs: T) -> Bool {
	return lhs.json.objectId == rhs.json.objectId
}

func ==(lhs: ParseType, rhs: ParseType) -> Bool {
	if let left = lhs as? Date {
		if let right = rhs as? Date {
			return left == right
		}
		return false
	}
	if let left = lhs as? Value {
		if let right = rhs as? Value {
			return left == right
		}
	}
	return false
}

func <(lhs: ParseType, rhs: ParseType) -> Bool {
	if let left = lhs as? Date {
		if let right = rhs as? Date {
			return left < right
		}
		return false
	}
	if let left = lhs as? Value {
		if let right = rhs as? Value {
			return left < right
		}
	}
	return false
}

//MARK: - Local Search & Cache

struct ClassCache {
	var inner: [Data] = []
	
	func data(objectId: String) -> Data? {
		for rec in inner {
			if rec.objectId == objectId {
				return rec
			}
		}
		return nil
	}
	
	mutating func appendData(data: Data) {
		var appended = false
		for i in 0..<inner.count {
			if inner[i].objectId == data.objectId {
				inner[i] = data
				appended = true
			}
		}
		if !appended {
			inner.append(data)
		}
	}
	
	mutating func removeData(data: Data) {
		var toRemove:[Int] = []
		for i in 0..<inner.count {
			if inner[i].objectId == data.objectId {
				toRemove.append(i)
			}
		}
		toRemove.map { self.inner.removeAtIndex($0) }
	}
}

struct LocalPersistence {
	static var classCache: [String: ClassCache] = [:]
	static let local_search_queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
	
	static func data(pointer: Pointer) -> Data? {
		if let recs = classCache[pointer.className] {
			return recs.data(pointer.objectId)
		}
		return nil
	}
	
	static func appendData(data: Data, pointer: Pointer) {
		if classCache[pointer.className] == nil {
			classCache[pointer.className] = ClassCache()
		}
		classCache[pointer.className]?.appendData(data)
	}
}

protocol LocalMatch {
	func match(json: Data) -> Bool
}

extension Query {
	func searchLocal(closure: ([String: AnyObject]?, NSError?) -> Void) -> Bool {
		if !useLocal || !constraints.allowsLocalSearch() {
			return false
		}
		if let cache = LocalPersistence.classCache[T.className]?.inner {
			dispatch_barrier_async(LocalPersistence.local_search_queue) {
				self.constraints.replaceSubQueries { (key, constraints) in
					if let innerCache = LocalPersistence.classCache[constraints.className]?.inner {
						return innerCache.filter { constraints.match($0) }.map { $0.value(key) }
					} else {
						return []
					}
				}
				var results: [Data] = []
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
				
				sort(&results, keys: self.order)
				
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
						result["results"] = results.map({ $0.raw })
					}
					closure(result, nil)
				}
			}
			return true
		}
		return false
	}
}

func sort(inout results: [Data], #keys: String?) {
	if var order = keys {
		let orders = split(order) { $0 == "," }
		var comparators: [(String, Bool)] = []
		for key in orders {
			let desc = key.hasPrefix("-")
			if desc {
				let key = key.substringFromIndex(key.startIndex.successor())
				comparators.append(key, false)
			} else {
				comparators.append(key, true)
			}
		}
		sort(&results) {
			for (key, asc) in comparators {
				if $1[key] == $0[key] {
					continue
				}
				//xnor
				if $0[key] < $1[key] {
					return asc
				} else {
					return !asc
				}
			}
			return true
		}
	}
}

extension Constraint: LocalMatch {
	
	func match(json: Data) -> Bool {
		switch self {
		case .EqualTo(let key, let right):
			return json[key] == right
		case .GreaterThan(let key, let right):
			return right < json[key]
		case .LessThan(let key, let right):
			return json[key] < right
		case .MatchRegex(let key, let regexp):
			let string = json.value(key).string!
			return regexp.firstMatchInString(string, options: nil, range: NSMakeRange(0, count(string))) != nil
		case .In(let key, let keys):
			return contains(keys, json.value(key))
		case .NotIn(let key, let keys):
			return !contains(keys, json.value(key))
		case .Or(let left, let right):
			return left.match(json) || right.match(json)
		case .Exists(let key, let exists):
			let isNil = json.value(key).type == .Null
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
				if let pointer = to as? Pointer {
					return false
				}
			default:
				continue
			}
		}
		return true
	}
	
	mutating func replaceSubQueries(keys: (String, Constraints) -> [Value]) {
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
	
	func match(json: Data) -> Bool {
		for constraint in inner {
			let match = constraint.match(json)
			if !match {
				return false
			}
		}
		return true
	}
}

extension _Query {
	func paging(group: dispatch_group_t, skip: Int = 0, block: ([[String: AnyObject]]) -> Void) {
		dispatch_group_enter(group)
		self.limit(1000).skip(skip).getRaw { (objects, error) in
			if let objects = objects {
				if let results = objects["results"] as? [[String: AnyObject]] {
					if results.count == 1000 {
						self.paging(group, skip: skip + 1000, block: block)
					}
					block(results)
				}
			}
			dispatch_group_leave(group)
		}
	}
	
	public func each(group: dispatch_group_t, block: ([String: AnyObject]) -> Void) {
		self.paging(group, skip: 0) { $0.map(block); return }
	}
	
	public func each(group: dispatch_group_t, concurrent: Int, block: ([String: AnyObject], () -> ()) -> Void) {
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
}

struct LocalCache<T: ParseObject> {
	static func loadCache() -> [String: AnyObject]? {
		let key = "v3.\(T.className).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			let file = root.stringByAppendingPathComponent(key)
			if let data = NSData(contentsOfFile: file) {
				println("loading from file \(file)")
				if let json = NSJSONSerialization.JSONObjectWithData(data, options: .AllowFragments, error: nil) as? [String: AnyObject] {
					return json
				}
			}
		}
		return nil
	}
	
	static func writeCache(json: [String: AnyObject]) {
		let key = "v3.\(T.className).json"
		let paths = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)
		if let root = paths.first as? NSString {
			NSJSONSerialization.dataWithJSONObject(json, options: nil, error: nil)?
				.writeToFile(root.stringByAppendingPathComponent(key), atomically: true)
			println("\(T.className) data wrote to \(root.stringByAppendingPathComponent(key))")
		}
	}
	
	static func append(dom: Data) {
		if let cache = self.loadCache() {
			var results = cache["results"] as! [String: AnyObject]
			results[dom.objectId] = dom.raw
			LocalPersistence.classCache[T.className]?.appendData(dom)
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": results,
				"class": T.className]
			self.writeCache(json)
		}
	}
	
	static func remove(dom: Data) {
		if let cache = self.loadCache() {
			var results = cache["results"] as! [String: AnyObject]
			results.removeValueForKey(dom.objectId)
			LocalPersistence.classCache[T.className]?.removeData(dom)
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": results,
				"class": T.className]
			self.writeCache(json)
		}
	}
	
	static func persistent(maxAge: NSTimeInterval, done: ([Data] -> Void)?) {
		if let cache = self.loadCache() {
			if let time = cache["time"] as? Double {
				let cachedTime = NSDate(timeIntervalSinceReferenceDate: time)
				if cachedTime.timeIntervalSinceNow > -maxAge {
					if let cache = cache["results"] as? [String: [String: AnyObject]] {
						let allData = cache.values.array.map({ Data($0) })
						if allData.count > 0 {
							LocalPersistence.classCache[T.className] = ClassCache(inner: allData)
							println("use local data \(T.className) count=\(allData.count)")
							done?(allData)
							return
						}
					}
				}
			}
		}
		let group = dispatch_group_create()
		var cache: [String: AnyObject] = [:]
		var jsons: [Data] = []
		println("start caching all \(T.className)")
		
		Query<T>().local(false).each(group) { object in
			cache[object["objectId"] as! String] = object
			jsons.append(Data(object))
		}
		
		dispatch_group_notify(group, dispatch_get_main_queue()) {
			LocalPersistence.classCache[T.className] = ClassCache(inner: jsons)
			println("\(T.className) ready")
			let json: [String: AnyObject] = [
				"time": NSDate.timeIntervalSinceReferenceDate(),
				"results": cache,
				"class": T.className]
			self.writeCache(json)
			done?(jsons)
		}
	}
}

//MARK: - Relations

public class Relation {
	var cache: [Pointer] = []
	
	func addObject(object: Pointer) {
		removeObjectId(object.objectId)
		cache.append(object)
	}
	
	func addObject<U: ParseObject>(object: U) {
		addObject(Pointer(object: object))
	}
	
	func removeObjectId(object: String) {
		cache = cache.filter { $0.objectId != object}
	}
	
	func contains<U: ParseObject>(object: U) -> Bool {
		return contains(object.json.objectId)
	}
	
	func contains(objectId: String) -> Bool {
		for p in cache {
			if p.objectId == objectId {
				return true
			}
		}
		return false
	}
	
	var count: Int {
		return cache.count
	}
}

public struct Relations {
	private static var relations: [String: (dispatch_group_t, Relation)] = [:]
	
	public static func of<T: ParseObject, U: ParseObject>(object: T, key: String, toType: U.Type, closure: (Relation) -> Void) {
		of(Pointer(object: object), key: key, toClass: U.className, closure: closure)
	}
	
	public static func of<T: ParseObject, U: ParseObject>(type: T.Type, key: String, to: U, closure: (Relation) -> Void) {
		let mykey = "\(key)-\(T.className)-\(U.className)/\(to.json.objectId)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			var relation = Relation()
			var group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			Query<T>().local(false).whereKey(key, equalTo: to).list { (data, error) in
				relation.cache = data.map { Pointer(className: T.className, data: $0) }
				println("caching relationship \(mykey): \(relation.cache)")
				dispatch_group_leave(group)
			}
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		}
	}
	
	public static func of(pointer: Pointer, key: String, toClass: String, closure: (Relation) -> Void) {
		let mykey = "\(key)-\(pointer.className)/\(pointer.objectId)-\(toClass)"
		if let (group, relation) = relations[mykey] {
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		} else {
			var relation = Relation()
			var group = dispatch_group_create()
			relations[mykey] = (group, relation)
			dispatch_group_enter(group)
			_Query(className: toClass, constraints: .RelatedTo(key, pointer)).list { (data, error) in
				relation.cache = data.map { Pointer(className: toClass, data: $0) }
				println("caching relationship \(mykey): \(relation.cache)")
				dispatch_group_leave(group)
			}
			dispatch_group_notify(group, dispatch_get_main_queue()) {
				closure(relation)
			}
		}
	}
}

extension ObjectOperations {
	func updateRelations() {
		let this = Pointer(className: T.className, objectId: objectId)
		for operation in operations {
			switch operation {
			case .AddRelation(let key, let pointer):
				Relations.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.addObject(pointer)
				}
			case .RemoveRelation(let key, let pointer):
				Relations.of(this, key: key, toClass: pointer.className) { (relation) in
					relation.removeObjectId(pointer.objectId)
				}
			default:
				continue
			}
		}
	}
}

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
		var pathString = "https://api.parse.com/1\(path)"
		var encoding: ParameterEncoding
		switch method {
		case .POST, .PUT:
			encoding = .JSON
		default:
			encoding = .URL
		}
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) {
			var request = self.manager!.request(method, pathString, parameters: parameters, encoding: encoding)
			request.responseJSON { (req, res, json, error) in
				if let object = json as? [String: AnyObject] {
					if object["error"] != nil && object["code"] != nil {
						closure(nil, NSError(domain: ParseErrorDomain, code: object["code"] as! Int, userInfo: [NSLocalizedDescriptionKey: object["error"] as! String]))
						return
					}
					closure(object, error)
				} else {
					closure(nil, error)
				}
			}
			return
		}
	}
	
	static func request(method: Method, _ path: String, _ data: NSData, _ closure: ([String: AnyObject]?, NSError?) -> Void) {
		var pathString = "https://api.parse.com/1\(path)"
		dispatch_group_notify(manager_init_group, dispatch_get_main_queue()) { () -> Void in
			var request = self.manager!.upload(method, pathString, data: data)
			request.responseJSON(options: nil) { (req, res, json, error) in
				if let object = json as? [String: AnyObject] {
					if object["error"] != nil && object["code"] != nil {
						closure(nil, NSError(domain: ParseErrorDomain, code: object["code"] as! Int, userInfo: [NSLocalizedDescriptionKey: object["error"] as! String]))
						return
					}
					closure(object, error)
				} else {
					closure(nil, error)
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
	
	public static func setup(#applicationId: String, restKey: String?, masterKey: String? = nil) {
		var configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
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
			println("trackAppOpen error = \(error)")
		}
	}
	
	public static func uploadImage(data: NSData, fileName: String, callback: (String?, NSError?) -> Void) {
		let name = "/files/\(fileName).jpg"
		Client.request(.POST, name, data) { (json, error) -> Void in
			if let error = error {
				return callback(nil, error)
			}
			if let json = json {
				callback(json["url"] as? String, error)
			}
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

extension ClassOperations {
	public func save(closure: (T?, NSError?) -> Void) {
		let param = _composeQuery(self)
		let _path = path(T.className)
		println("saving \(param) to \(_path)")
		Client.request(.POST, _path, param) { (json, error) in
			if let error = error {
				closure(nil, error)
				return
			}
			if let json = json {
				var object = param
				object["createdAt"] = json["createdAt"]
				object["objectId"] = json["objectId"]
				let data = Data(object)
				LocalCache<T>.append(data)
				closure(T(json: data), nil)
			}
		}
	}
}

extension ObjectOperations {
	public func update(closure: (NSError?) -> Void) {
		var param: [String: AnyObject] = [:]
		for operation in operations {
			operation.composeQuery(&param)
		}
		let _path = path(T.className, objectId: objectId)
		println("updating \(param) to \(_path)")
		Client.request(.PUT, _path, param) { (json, error) in
			if let json = json {
				self.updateRelations()
			}
			closure(error)
		}
	}
	
	public func delete(closure: (NSError?) -> Void) {
		let _path = path(T.className, objectId: objectId)
		Client.request(.DELETE, _path, [:]) { (json, error) in
			closure(error)
		}
	}
}

public func parseFunction(name: String, parameters: [String: AnyObject], done: ([String: AnyObject]?, NSError?) -> Void) {
	Client.request(.POST, "/functions/\(name)", parameters, done)
}



extension Parse {
	public func persistent(maxAge: NSTimeInterval, done: ([Data] -> Void)? = nil) -> Self {
		LocalCache<T>.persistent(maxAge, done: done)
		return self
	}
}

//MARK: - Printable & Convertible

extension Value: IntegerLiteralConvertible {
	public init(integerLiteral value: IntegerLiteralType) {
		object = value
		type = .Number
	}
}

extension Value: StringLiteralConvertible {
	public init(unicodeScalarLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
	public init(stringLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
	public init(extendedGraphemeClusterLiteral value: StringLiteralType) {
		object = value
		type = .String
	}
}

extension Value: FloatLiteralConvertible {
	public init(floatLiteral value: FloatLiteralType) {
		object = value
		type = .Number
	}
}

extension Data: DictionaryLiteralConvertible {
	public init(dictionaryLiteral elements: (String, AnyObject)...) {
		var dictionary_ = [String : AnyObject]()
		for (key_, value) in elements {
			dictionary_[key_] = value
		}
		self.init(dictionary_)
	}
}

extension Pointer: Printable {
	public var description: String {
		var string = "*\(className).\(objectId)"
		if let conn = connections {
			string += " ["
			string += ", ".join(map(conn) { "\($0):\($1)" })
			string += "]"
		}
		return string
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

//MARK: Cache

public struct ObjectCache {
	static var timers: [String: (dispatch_source_t, [(objectId: String, closure: Data -> Void)])] = [:]
	
	static func timer(key: String) -> dispatch_source_t {
		if let timer = timers[key] {
			return timer.0
		}
		let timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue())
		dispatch_resume(timer)
		timers[key] = (timer, [])
		return timer
	}
	
	static func retrivePending<T: ParseObject>(type: T.Type) -> [(objectId: String, closure: Data -> Void)] {
		if var (timer, pending) = timers[T.className] {
			let checkouts = pending
			timers[T.className] = (timer, [])
			return checkouts
		}
		return []
	}
	
	static func appendClosure<T: ParseObject>(objectId: String, closure: (T) -> Void) {
		if var (timer, pending) = timers[T.className] {
			pending.append(objectId: objectId, closure: { closure(T(json: $0)) })
			timers[T.className] = (timer, pending)
		}
	}
	
	public static func get<T: ParseObject>(objectId: String, rush: Double = 0.25, closure: (T) -> Void) {
		if let object = LocalPersistence.data(Pointer(className: T.className, objectId: objectId)) {
			return closure(T(json: object))
		} else {
			let t = timer(T.className)
			appendClosure(objectId, closure: closure)
			dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, Int64(rush * Double(NSEC_PER_SEC))), DISPATCH_TIME_FOREVER, 0)
			dispatch_source_set_event_handler(t) {
				let checkouts = self.retrivePending(T.self)
				let objectIds = checkouts.map { Value($0.objectId) }
				_Query(className: T.className, constraints: .In("objectId", objectIds)).list { (jsons, error) in
					for (objectId, closure) in checkouts {
						for json in jsons {
							if json.objectId == objectId {
								LocalPersistence.appendData(json, pointer: Pointer(className: T.className, objectId: objectId))
								closure(json)
								break
							}
						}
					}
				}
			}
		}
	}
}
