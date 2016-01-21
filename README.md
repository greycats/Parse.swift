# SwiftyParse

[![CI Status](http://img.shields.io/travis/Rex Sheng/SwiftyParse.svg?style=flat)](https://travis-ci.org/Rex Sheng/SwiftyParse)
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

    // then you can sync with your models to local, or not
    // you can create your model as class or struct
    // Models natually have objectId, createdAt, updatedAt and security fields. And File, User, Installation, Push models are already defined for you.

    guard let me = User.currentUser else { return }

    struct Document: ParseObject {
    	static let className = "Document"
    	var json: Data!
    	init() {}
    	let title = Field<String>("title")
    	let description = Field<String>("description")
    	let author = Field<User>("author")
    }

    // you can optionally pre-load all documents to file, and queries later on will be performed locally instead of remotely.
    Document.persistent(86400)

    // to perform a query, for more query options, see Query.swift
    Document.query().list { documents, error in
        ...
    }
    Document.query().local(false).order("-updatedAt,title").relatedTo(me, key: "master_piece").list { documents, error in
        for document in documents {
            print(document.title.get())
        }
    }

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

