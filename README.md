# Parse.swift

[![CI Status](http://img.shields.io/travis/Rex Sheng/SwiftyParse.svg?style=flat)](https://travis-ci.org/Rex Sheng/SwiftyParse)
[![Version](https://img.shields.io/cocoapods/v/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![License](https://img.shields.io/cocoapods/l/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![Platform](https://img.shields.io/cocoapods/p/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)

## Usage

```swift

    setup(applicationId: "<# your application id #>", restKey: "<# rest key #>")

    // then you can sync with your models

    let authors = Parse<Author>().persistToLocal(maxAge: 86400)
    let documents = Parse<Document>()

    class Author: ParseObject {
  
        class var className: String { return "authors"}
        var json: JSON?
        var firstName: String?
        var lastName: String?
        var birth: Int?
        var id: Int
    
        required init(json: JSON) {
            self.json = json
            id = json["id"].intValue
            birth = json["birth"].int
            firstName = json["first_name"].string
            lastName = json["last_name"].string
        }
    }
    
    class Document: ParseObject {
        var title: String
        var author: Int?
        var link: String?
        var downloaded: Int?
    
        required init(json: JSON) {
            title = json["title"].stringValue
            author = json["author_id"].int
            link = json["link"].string
            downloaded = json["downloaded"].int
        }
    
        class func search(term: NSRegularExpression, then: ([Document], NSError?) -> Void) {
            documents.query().whereKey("title", match: term).order("-downloaded").limit(50).get(then)
        }
    
        class func documentsByAuthorName(firstName: String, last_name: String, birth: Int, then: ([Document], NSError?) -> Void) {
            let firstNameQuery = authors.query()
                .whereKey("first_name", equalTo: firstName)
                .whereKey("birth", greaterThan: birth)
            let lastNameQuery = authors.query()
                .whereKey("last_name", equalTo: lastName)
                .whereKey("birth", greaterThan: birth)
            let authorQuery = firstNameQuery || lastNameQuery
            documents.query().whereKey("author_id", matchKey: "id", inQuery: authorQuery).get(then)
        }
    }
```

* with `persistToLocal` phrase, authors will sync to local (your document directory), with defined primary key and max expire age. After then, all queries / subqueries to author, will be using local data if possible.
* you can use swift infix operators `||` on queries
* `ParseObject` is a simple protocol. (You can use struct as you like)
* save / update / relation / pointer queries all using generic types
* ... full stack support

## Requirements

## Installation

Greycats.swift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

    pod "SwiftyParse"

## Author

Rex Sheng, shengning@gmail.com

## License

SwiftyParse is available under the MIT license. See the LICENSE file for more info.

