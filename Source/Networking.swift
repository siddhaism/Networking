import Foundation
import TestCheck
import JSON

#if os(iOS) || os(tvOS) || os(watchOS)
    import UIKit
#endif

public class Networking {
    private enum RequestType: String {
        case GET, POST
    }

    private let baseURL: String
    private var stubs: [RequestType : [String : AnyObject]]
    private var session = NSURLSession.sharedSession()

    /**
     Base initializer, it creates an instance of `Networking`.
     - parameter baseURL: The base URL for HTTP requests under `Networking`.
     */
    public init(baseURL: String) {
        self.baseURL = baseURL
        self.stubs = [RequestType : [String : AnyObject]]()
    }

    /**
     Authenticates using Basic Authentication, it converts username:password to Base64 then sets the
     Authorization header to "Basic \(Base64(username:password))"
     - parameter username: The username to be used
     - parameter password: The password to be used
     */
    public func autenticate(username: String, password: String) {
        let credentialsString = "\(username):\(password)"
        if let credentialsData = credentialsString.dataUsingEncoding(NSUTF8StringEncoding) {
            let base64Credentials = credentialsData.base64EncodedStringWithOptions([])
            let authString = "Basic \(base64Credentials)"

            let config  = NSURLSessionConfiguration.defaultSessionConfiguration()
            config.HTTPAdditionalHeaders = ["Authorization" : authString]

            self.session = NSURLSession(configuration: config)
        }
    }

    private var token: String?

    /**
     Authenticates using a token, sets the Authorization header to "Bearer \(token)"
     - parameter token: The token to be used
     */
    public func autenticate(token: String) {
        self.token = token
    }

    // MARK: GET

    /**
    GET request to the specified path.
    - parameter path: The path for the GET request.
    - parameter completion: A closure that gets called when the GET request is completed, it contains a `JSON` object and a `NSError`.
    */
    public func GET(path: String, completion: (JSON: AnyObject?, error: NSError?) -> ()) {
        self.request(.GET, path: path, parameters: nil, completion: completion)
    }

    /**
     Stubs GET request for the specified path. After registering this, every GET request to the path, will return
     the registered response.
     - parameter path: The path for the stubbed GET request.
     - parameter response: An `AnyObject` that will be returned when a GET request is made to the specified path.
     */
    public func stubGET(path: String, response: AnyObject) {
        self.stub(.GET, path: path, response: response)
    }

    /**
     Stubs GET request for the specified path using the contents of a file. After registering this, every GET request to the path, will return
     the contents of the registered file.
     - parameter path: The path for the stubbed GET request.
     - parameter fileName: The name of the file, whose contents will be registered as a reponse.
     - parameter bundle: The NSBundle where the file is located.
     */
    public func stubGET(path: String, fileName: String, bundle: NSBundle = NSBundle.mainBundle()) {
        self.stub(.GET, path: path, fileName: fileName, bundle: bundle)
    }

    // MARK: - POST

    /**
    POST request to the specified path, using the provided parameters.
    - parameter path: The path for the GET request.
    - parameter parameters: The parameters to be used, they will be serialized using NSJSONSerialization.
    - parameter completion: A closure that gets called when the POST request is completed, it contains a `JSON` object and a `NSError`.
    */
    public func POST(path: String, parameters: AnyObject?, completion: (JSON: AnyObject?, error: NSError?) -> ()) {
        self.request(.POST, path: path, parameters: parameters, completion: completion)
    }

    /**
    Stubs POST request for the specified path. After registering this, every POST request to the path, will return
     the registered response.
     - parameter path: The path for the stubbed POST request.
     - parameter response: An `AnyObject` that will be returned when a POST request is made to the specified path.
     */
    public func stubPOST(path: String, response: AnyObject) {
        self.stub(.POST, path: path, response: response)
    }

    /**
    Stubs POST request to the specified path using the contents of a file. After registering this, every POST request to the path, will return
     the contents of the registered file.
     - parameter path: The path for the stubbed POST request.
     - parameter fileName: The name of the file, whose contents will be registered as a reponse.
     - parameter bundle: The NSBundle where the file is located.
     */
    public func stubPOST(path: String, fileName: String, bundle: NSBundle = NSBundle.mainBundle()) {
        self.stub(.POST, path: path, fileName: fileName, bundle: bundle)
    }

    // MARK: Image

    /**
    Downloads an image using the specified path.
    - parameter path: The path where the image is located
    - parameter completion: A closure that gets called when the image download request is completed, it contains an `UIImage` object and a `NSError`.
    */
    public func downloadImage(path: String, completion: (image: UIImage?, error: NSError?) -> ()) {
        if let getStubs = self.stubs[.GET], image = getStubs[path] as? UIImage {
            completion(image: image, error: nil)
        } else {
            let request = NSMutableURLRequest(URL: self.urlForPath(path))
            request.HTTPMethod = "GET"
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            let semaphore = dispatch_semaphore_create(0)
            var returnedData: NSData?
            var returnedImage: UIImage?
            var returnedError: NSError?
            var returnedResponse: NSURLResponse?

            #if os(iOS)
                if Test.isRunning() == false {
                    dispatch_async(dispatch_get_main_queue(), {
                        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                    })
                }
            #endif

            self.session.downloadTaskWithRequest(request, completionHandler: { url, response, error in
                returnedResponse = response
                returnedError = error

                if let url = url, data = NSData(contentsOfURL: url), image = UIImage(data: data) {
                    returnedData = data
                    returnedImage = image
                }

                if Test.isRunning() {
                    dispatch_semaphore_signal(semaphore)
                } else {
                    dispatch_async(dispatch_get_main_queue(), {
                        #if os(iOS)
                            UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                        #endif

                        self.logError(nil, data: returnedData, request: request, response: response, error: error)
                        completion(image: returnedImage, error: error)
                    })
                }
            }).resume()

            if Test.isRunning() {
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)

                self.logError(nil, data: returnedData, request: request, response: returnedResponse, error: returnedError)
                completion(image: returnedImage, error: returnedError)
            }
        }
    }

    /**
     Stubs a download image request with an UIImage. After registering this, every download request to the path, will return
     the registered UIImage.
     - parameter path: The path for the stubbed image download.
     - parameter image: A UIImage that will be returned when there's a request to the registered path
     */
    public func stubImageDownload(path: String, image: UIImage) {
        self.stub(.GET, path: path, response: image)
    }

    // MARK: - Utilities

    /**
    Generates a NSURL by appending the provided path to the Networking's base URL.
    - parameter path: The path to be appended to the base URL.
    - returns: A NSURL generated after appending the path to the base URL.
    */
    public func urlForPath(path: String) -> NSURL {
        return NSURL(string: self.baseURL + path)!
    }
}

// MARK: - Private

extension Networking {
    private func stub(requestType: RequestType, path: String, fileName: String, bundle: NSBundle = NSBundle.mainBundle()) {
        do {
            if let result = try JSON.from(fileName, bundle: bundle) {
                self.stub(requestType, path: path, response: result)
            }
        } catch ParsingError.NotFound {
            fatalError("We couldn't find \(fileName), are you sure is there?")
        } catch {
            fatalError("Converting data to JSON failed")
        }
    }

    private func stub(requestType: RequestType, path: String, response: AnyObject) {
        var getStubs = self.stubs[requestType] ?? [String : AnyObject]()
        getStubs[path] = response
        self.stubs[requestType] = getStubs
    }

    private func request(requestType: RequestType, path: String, parameters: AnyObject?, completion: (JSON: AnyObject?, error: NSError?) -> ()) {
        if let responses = self.stubs[requestType], response = responses[path] {
            completion(JSON: response, error: nil)
        } else {
            let request = NSMutableURLRequest(URL: self.urlForPath(path))
            request.HTTPMethod = requestType.rawValue
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept")

            if let token = token {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            #if os(iOS)
                if Test.isRunning() == false {
                    dispatch_async(dispatch_get_main_queue(), {
                        UIApplication.sharedApplication().networkActivityIndicatorVisible = true
                    })
                }
            #endif

            var serializingError: NSError?
            if let parameters = parameters {
                do {
                    request.HTTPBody = try NSJSONSerialization.dataWithJSONObject(parameters, options: [])
                } catch let error as NSError {
                    serializingError = error
                }
            }

            if let serializingError = serializingError {
                dispatch_async(dispatch_get_main_queue(), {
                    completion(JSON: nil, error: serializingError)
                })
            } else {
                var connectionError: NSError?
                var result: AnyObject?
                let semaphore = dispatch_semaphore_create(0)
                var returnedResponse: NSURLResponse?
                var returnedData: NSData?

                self.session.dataTaskWithRequest(request, completionHandler: { data, response, error in
                    returnedResponse = response
                    connectionError = error
                    returnedData = data

                    if let data = data {
                        do {
                            result = try NSJSONSerialization.JSONObjectWithData(data, options: .MutableLeaves)
                        } catch let serializingError as NSError {
                            if error == nil {
                                connectionError = serializingError
                            }
                        }
                    }

                    if Test.isRunning() {
                        dispatch_semaphore_signal(semaphore)
                    } else {
                        dispatch_async(dispatch_get_main_queue(), {
                            #if os(iOS)
                                UIApplication.sharedApplication().networkActivityIndicatorVisible = false
                            #endif

                            self.logError(parameters, data: returnedData, request: request, response: returnedResponse, error: connectionError)
                            completion(JSON: result, error: connectionError)
                        })
                    }
                }).resume()

                if Test.isRunning() {
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER)
                    self.logError(parameters, data: returnedData, request: request, response: returnedResponse, error: connectionError)
                    completion(JSON: result, error: connectionError)
                }
            }
        }
    }

    private func logError(parameters: AnyObject? = nil, data: NSData?, request: NSURLRequest?, response: NSURLResponse?, error: NSError?) {
        guard let error = error else { return }

        print(" ")
        print("========== Networking Error ==========")
        print(" ")

        print("Error \(error.code): \(error.description)")
        print(" ")

        if let request = request {
            print("Request: \(request)")
            print(" ")
        }

        if let parameters = parameters {
            print("parameters: \(parameters)")
            print(" ")
        }

        if let data = data, stringData = NSString(data: data, encoding: NSUTF8StringEncoding) {
            print("Data: \(stringData)")
            print(" ")
        }

        if let response = response as? NSHTTPURLResponse {
            print("Response status code: \(response.statusCode)")
            print(" ")
            print("Path: \(response.URL!.absoluteString)")
            print(" ")
            print("Response: \(response)")
            print(" ")
        }

        print("================= ~ ==================")
        print(" ")
    }
}
