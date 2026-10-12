import Foundation

/// Accepts connections from Foyer (the only process that can reach an
/// embedded XPC service) and wires up the bidirectional interface:
/// `FoyerHelperProtocol` exported, `FoyerHelperClientProtocol` remote.
final class HelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = HelperXPCInterfaces.helperInterface()
        newConnection.remoteObjectInterface = HelperXPCInterfaces.clientInterface()

        let service = FoyerHelperService(connection: newConnection)
        newConnection.exportedObject = service
        newConnection.invalidationHandler = { [weak service] in
            service?.connectionDidInvalidate()
        }
        newConnection.interruptionHandler = { [weak service] in
            service?.connectionDidInvalidate()
        }
        newConnection.resume()
        return true
    }
}
