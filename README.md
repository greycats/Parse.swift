# Parse.swift

[![CI Status](http://img.shields.io/travis/Rex Sheng/SwiftyParse.svg?style=flat)](https://travis-ci.org/Rex Sheng/SwiftyParse)
[![Version](https://img.shields.io/cocoapods/v/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![License](https://img.shields.io/cocoapods/l/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![Platform](https://img.shields.io/cocoapods/p/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)

## Usage

```swift

setup(applicationId: "<# your application id #>", restKey: "<# rest key #>")

// then you can sync with your models

let authors = Parse<Author>("authors").persistToLocal(maxAge: 86400)
let documents = Parse<Document>("documents")

class Author: ParseObject {
    var firstName: String?
    var lastName: String?
    var birth: Int?
    var id: Int
    
    required init(json: JSON) {
        id = json["author_id"].intValue
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
        author = json["author"].string
        link = json["link"].string
        downloaded = json["downloaded"].int
    }
    
    class func search(term: NSRegularExpression, then: ([Document], NSError?) -> Void) {
        documents.query().whereKey("title", match: term).order("-downloaded").limit(50).get(then)
    }
    
    class func documentsByAuthorName(firstName: String, last_name: String, birth: Int, then: ([Document], NSError?) -> Void) {
        let firstNameQuery = authors.query().whereKey("first_name", equalTo: firstName)
        let lastNameQuery = authors.query().whereKey("last_name", equalTo: lastName)
        let ageQuery = authors.query().whereKey("birth", greaterThan: birth)
        let authorQuery = (firstNameQuery || lastNameQuery) && ageQuery
        
        documents.query().whereKey("author_id", matchKey: "id", inQuery: authorQuery).get(then)
    }
}
```

* With `persistToLocal` phrase, authors will sync to local (your document directory), with defined primary key and max expire age. After then, all queries / subqueries to author, will be using local data if possible.
* you can use swift infix operators `||` and `&&` on queries.
* Notice generic support

## Requirements

## Installation

Greycats.swift is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

    pod "SwiftyParse"

## Author

Rex Sheng, shengning@gmail.com

## License

SwiftyParse is available under the MIT license. See the LICENSE file for more info.

