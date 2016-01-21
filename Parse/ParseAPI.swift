//
//  ParseAPI.swift
//  Parse
//
//  Created by Rex Sheng on 1/15/16.
//  Copyright © 2016 Rex Sheng. All rights reserved.
//

//MARK: - Parse API Composer

protocol QueryComposer {
	func composeQuery(inout param: [String: AnyObject])
}

private func _composeQuery(composer: QueryComposer) -> [String : AnyObject] {
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
			if match.options.contains(.CaseInsensitive) {
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

//MARK: - Shortcut Methods

extension _Query {
	private func client() -> Parse {
		var parameters: [String: AnyObject] = [:]
		var _where: [String: AnyObject] = [:]
		self.composeQuery(&_where)
		if _where.count > 0 {
			if let data = try? NSJSONSerialization.dataWithJSONObject(_where, options: []) {
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
		return Parse.Get(_path, parameters)
	}

	public func data(closure: ([Data], ErrorType?) -> Void) {
		client().response(searchLocal) { (json, error) in
			if let json = json {
				if let array = json["results"] as? [[String: AnyObject]] {
					closure(array.map { Data($0) }, error)
					return
				}
			}
			closure([], error)
		}
	}

	public func count(closure: (Int, ErrorType?) -> Void) {
		fetchesCount = true
		limit(1)
		client().response { (json, error) in
			if let json = json {
				if let count = json["count"] as? Int {
					closure(count, error)
					return
				}
			}
			closure(0, error)
		}
	}

	func paging(group: dispatch_group_t, skip: Int = 0, block: ([[String: AnyObject]]) -> Void) {
		dispatch_group_enter(group)
		limit(1000).skip(skip).client().response { (objects, error) in
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
		paging(group, skip: 0) { $0.forEach(block); return }
	}

	public func each(group: dispatch_group_t, concurrent: Int, block: ([String: AnyObject], () -> ()) -> Void) {
		let semophore = dispatch_semaphore_create(concurrent)
		let queue = dispatch_queue_create(nil, DISPATCH_QUEUE_CONCURRENT)
		each(group) { (json) in
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

extension Query {
	public func list(closure: ([T], ErrorType?) -> Void) {
		data { (data, error) in
			closure(data.map { T(json: $0) }, error)
		}
	}

	public func first(closure: (T?, ErrorType?) -> Void) {
		limit(1).list { (ts, error) in
			closure(ts.first, error)
		}
	}
}

extension Constraint: CustomStringConvertible {
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

extension Constraints: CustomStringConvertible {
	public var description: String {
		return "\(inner)"
	}
}

//MARK: Operation

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
		case .ClearSecurity:
			param["ACL"] = ACL(rules: [ACLRule(name: "*", write: true, read: true)]).json
		case .DeleteColumn(let key):
			param[key] = ["__op": "Delete"]
		}
	}
}

func path(className: String, objectId: String? = nil) -> String {
	var path: String
	switch className {
	case "_User":
		path = "users"
	case "_Installation":
		path = "installations"
	default:
		path = "classes/\(className)"
	}
	if let objectId = objectId {
		path += "/\(objectId)"
	}
	return path
}

extension ObjectOperations {
	public func update(closure: (ErrorType?) -> Void) {
		var param: [String: AnyObject] = [:]
		for operation in operations {
			operation.composeQuery(&param)
		}

		let _path = path(T.className, objectId: objectId)
		print("updating \(param) to \(_path)")
		Parse.Put(_path, param).response { (json, error) in
			if let json = json {
				let cache = LocalCache(className: T.className)
				if var data = cache.data(self.objectId)?.raw {
					for operation in self.operations {
						switch operation {
						case .SetValue(let key, let args):
							data[key] = args.json
						default:
							break
						}
					}
					data["updatedAt"] = json["updatedAt"]
					cache.append(Data(data))
				}
				self.updateRelations()
			}
			closure(error)
		}
	}

	public func delete(closure: (ErrorType?) -> Void) {
		let _path = path(T.className, objectId: objectId)
		Parse.Delete(_path, nil).response { (json, error) in
			closure(error)
		}
	}
}

extension ClassOperations: QueryComposer {
	func composeQuery(inout param: [String : AnyObject]) {
		for operation in operations {
			operation.composeQuery(&param)
		}
	}

	public func save(closure: (T?, ErrorType?) -> Void) {
		let param = _composeQuery(self)
		let _path = path(T.className)
		print("saving \(param) to \(_path)")
		Parse.Post(_path, param).response { (json, error) in
			if let error = error {
				closure(nil, error)
				return
			}
			if let json = json {
				var object = param
				object["createdAt"] = json["createdAt"]
				object["objectId"] = json["objectId"]
				let data = Data(object)
				LocalCache(className: T.className).append(data)
				closure(T(json: data), nil)
			}
		}
	}
}