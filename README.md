# SwiftyParse

[![Build Status](https://travis-ci.org/greycats/Parse.swift.svg?branch=master)](https://travis-ci.org/greycats/Parse.swift)
[![Version](https://img.shields.io/cocoapods/v/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![License](https://img.shields.io/cocoapods/l/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)
[![Platform](https://img.shields.io/cocoapods/p/SwiftyParse.svg?style=flat)](http://cocoadocs.org/docsets/SwiftyParse)

## Installation

SwiftyParse is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

    pod "SwiftyParse"


## Usage

```swift
import SwiftyParse

// first of all, set up Parse using RestKey
Parse.setup(applicationId: "<# your application id #>", restKey: "<# rest key #>")
// or MasterKey
Parse.setup(applicationId: "<# your application id #>", masterKey: "<# master key #>")

// Models natually have objectId, createdAt, updatedAt and security fields. And File, User, Installation, Push models are already defined for you.
// You can create your model as class or struct

struct Document: ParseObject {
	static let className = "Document"
	var json: Data!
	init() {}
	let title = Field<String>("title")
	let description = Field<String>("description")
	let author = Field<User>("author")
}

// To log in user
User.logIn("username", password: "password") { user, error in
}

// Let us assume user is already logged in in this snippet
guard let me = User.currentUser else { return }

// you can optionally pre-load all documents to file, and queries later on will be performed locally as much as possible.
Document.persistent(86400)

// to perform a query
Document.query().list { documents, error in
    ...
}
Document.query().local(false).order("-updatedAt,title").relatedTo(me, key: "master_piece").list { documents, error in
    for document in documents {
        print(document.title.get())
    }
}
// for more query options, see Query.swift

// to perform an update or curation
Document.opertation().set("author", value: me).save { document, error in 
    if let document = document {
        document.title.set("SwiftyParse")
        document.update { error in
            ...
        }
    }
}

// and much more features you can discover
let firstNameQuery = User.query().whereKey("first_name", equalTo: firstName).whereKey("birth", greaterThan: birth)
let lastNameQuery = User.query().whereKey("last_name", equalTo: lastName).whereKey("birth", greaterThan: birth)
let authorQuery = firstNameQuery || lastNameQuery
Document.query().whereKey("author", matchKey: "id", inQuery: authorQuery).get { documents, error in
    for document in documents {
        document.operation().setSecurity(me).update { _ in }
    }
}
```
    
Operations are affecting data in local storage too.

## Author

[Rex Sheng](http://github.com/b051)

## License

SwiftyParse is available under the MIT license. See the LICENSE file for more info.

