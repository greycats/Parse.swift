# SwiftyParse

[![CI Status](http://img.shields.io/travis/Rex Sheng/SwiftyParse.svg?style=flat)](https://travis-ci.org/Rex Sheng/SwiftyParse)
[![Version](https://img.shields.io/cocoapods/v/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![License](https://img.shields.io/cocoapods/l/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![Platform](https://img.shields.io/cocoapods/p/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)

## Usage

```swift
import Parse

Client.setup(applicationId: "<# your application id #>", restKey: "<# rest key #>")

// then you can sync with your models to local, or not

let authors = Parse<Author>().persistent(maxAge: 86400)

class Author: ParseObject {
    class var className: String { return "authors"}
    
    var json: Data?
    
    // you can link properies
    var createdAt: NSDate
    var firstName: String? {
    	return json?.value("first_name").string
    }
    
    required init(json: Data) {
        self.json = json
        createdAt = json.date("createdAt")
    }
    
    func documents(closure: ([Document], NSError?) -> Void) {
        Query<Document>().whereKey("author", equalTo: self).get(closure)
    }
}

class Document: ParseObject {
    class var className: String { return "documents"}
    
    var json: Data?
   
    required init(json: Data) {
        self.json = json
    }

    class func search(term: NSRegularExpression, then: ([Document], NSError?) -> Void) {
    	// defaults to local search
        documents.query().local(false).whereKey("title", match: term).order("-downloaded,name").limit(50).get(then)
    }

    class func documentsByAuthorName(firstName: String, last_name: String, birth: Int, then: ([Document], NSError?) -> Void) {
        let firstNameQuery = authors.query()
            .whereKey("first_name", equalTo: firstName)
            .whereKey("birth", greaterThan: birth)
        let lastNameQuery = authors.query()
            .whereKey("last_name", equalTo: lastName)
            .whereKey("birth", greaterThan: birth)
        let authorQuery = firstNameQuery || lastNameQuery
        Query<Document>().whereKey("author_id", matchKey: "id", inQuery: authorQuery).get(then)
    }
}
```

To replace author_id with author reference:
```swift
func convertBoard<T: ParseObject>(group: dispatch_group_t, type: T.Type) {
	Query<T>().whereKey("author_id", exists: true).each(group, concurrent: 4) { (json, complete) in
		let json = Data(raw: json)
		Query<Author>().whereKey("id", equalTo: json.value("author_id").string!).first { (author, error) in
			let oid = json.objectId
			if let author = author {
				Parse<T>.operation(oid, operations: .DeleteColumn("author_id"))
					.set("author", value: author).update { (json, error) in
						println("json = \(json) \(error)")
						complete()
				}
			} else {
				Parse<T>.operation(oid).delete { (error) in
					println("delete \(T.className) met error \(error)")
					complete()
				}
			}
		}
	}
}
```

* with `persistent` phrase, authors will sync to local (your document directory), with defined primary key and max expire age. After then, all queries / subqueries to author, will be using local data if possible.
* you can use swift infix operators `||` on queries
* `ParseObject` is a simple protocol. (You can use struct as you like)
* save / update / relation / pointer queries all using generic types
* automatically sync relationship to local, and update when add/remove relations

## Requirements

Alamofire

if you are targeting iOS7, I suggest you to grab the source code and comment out `import Alamofire`, yeah, and copy Alamofire to your project.

## Installation

SwiftyParse is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

    pod "SwiftyParse"

## Author

[Rex Sheng](http://github.com/b051)

## License

SwiftyParse is available under the MIT license. See the LICENSE file for more info.

