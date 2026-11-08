import Foundation

@objc public protocol RightClickActionRunnerXPCProtocol {
    @objc(performActionWithRequestData:reply:)
    func performAction(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)

    @objc(performMaintenanceWithRequestData:reply:)
    func performMaintenance(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void)
}

public final class RightClickActionRunnerXPCAdapter: NSObject, RightClickActionRunnerXPCProtocol {
    private let runner: ActionRunner
    private let maintenanceService: SystemMaintenanceService
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        runner: ActionRunner,
        maintenanceService: SystemMaintenanceService = SystemMaintenanceService()
    ) {
        self.runner = runner
        self.maintenanceService = maintenanceService
    }

    public func performAction(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        do {
            let request = try decoder.decode(ActionRequest.self, from: requestData as Data)
            let result = runner.run(request)
            let data = try encoder.encode(result)
            reply(data as NSData, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    public func performMaintenance(requestData: NSData, reply: @escaping (NSData?, NSError?) -> Void) {
        do {
            let request = try decoder.decode(SystemMaintenanceRequest.self, from: requestData as Data)
            let result = maintenanceService.perform(request)
            let data = try encoder.encode(result)
            reply(data as NSData, nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}

public enum RightClickXPCClientError: Error, LocalizedError {
    case unavailable
    case missingResponse

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "ActionRunner XPC 服务不可用"
        case .missingResponse:
            return "ActionRunner 没有返回结果"
        }
    }
}

public final class RightClickActionRunnerXPCClient {
    private let serviceName: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(serviceName: String = RightClickConstants.defaultXPCServiceName) {
        self.serviceName = serviceName
    }

    public func perform(_ request: ActionRequest, completion: @escaping (Result<ActionResult, Error>) -> Void) {
        do {
            let requestData = try encoder.encode(request)
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RightClickActionRunnerXPCProtocol.self)
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                completion(.failure(error))
            }) as? RightClickActionRunnerXPCProtocol else {
                connection.invalidate()
                completion(.failure(RightClickXPCClientError.unavailable))
                return
            }

            proxy.performAction(requestData: requestData as NSData) { responseData, error in
                connection.invalidate()

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let responseData else {
                    completion(.failure(RightClickXPCClientError.missingResponse))
                    return
                }

                do {
                    let result = try self.decoder.decode(ActionResult.self, from: responseData as Data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }

    public func performMaintenance(
        _ request: SystemMaintenanceRequest,
        completion: @escaping (Result<SystemMaintenanceResult, Error>) -> Void
    ) {
        do {
            let requestData = try encoder.encode(request)
            let connection = NSXPCConnection(serviceName: serviceName)
            connection.remoteObjectInterface = NSXPCInterface(with: RightClickActionRunnerXPCProtocol.self)
            connection.resume()

            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ error in
                connection.invalidate()
                completion(.failure(error))
            }) as? RightClickActionRunnerXPCProtocol else {
                connection.invalidate()
                completion(.failure(RightClickXPCClientError.unavailable))
                return
            }

            proxy.performMaintenance(requestData: requestData as NSData) { responseData, error in
                connection.invalidate()

                if let error {
                    completion(.failure(error))
                    return
                }

                guard let responseData else {
                    completion(.failure(RightClickXPCClientError.missingResponse))
                    return
                }

                do {
                    let result = try self.decoder.decode(SystemMaintenanceResult.self, from: responseData as Data)
                    completion(.success(result))
                } catch {
                    completion(.failure(error))
                }
            }
        } catch {
            completion(.failure(error))
        }
    }
}
