import Foundation
import CocoaAsyncSocket

/**
 The base proxy server class.

 This proxy does not listen on any port.
 */
open class ProxyServer: NSObject, TunnelDelegate {
    typealias TunnelArray = Atomic<[Tunnel]>

    /// The port of proxy server.
    open let port: Port

    /// The address of proxy server.
    open let address: IPv4Address?

    /// The type of the proxy server.
    ///
    /// This can be set to anything describing the proxy server.
    open let type: String

    /// The description of proxy server.
    open override var description: String {
        return "<\(type) address:\(String(describing: address)) port:\(port)>"
    }

    open var observer: Observer<ProxyServerEvent>?

    var tunnels: TunnelArray = Atomic([])

    /**
     Create an instance of proxy server.

     - parameter address: The address of proxy server.
     - parameter port:    The port of proxy server.

     - warning: If you are using Network Extension, you have to set address or you may not able to connect to the proxy server.
     */
    public init(address: IPv4Address?, port: Port) {
        self.address = address
        self.port = port
        type = "\(type(of: self))"

        super.init()

        self.observer = ObserverFactory.currentFactory?.getObserverForProxyServer(self)
    }

    /**
     Start the proxy server.

     - throws: The error occured when starting the proxy server.
     */
    open func start() throws {
        observer?.signal(.started(self))
    }

    /**
     Stop the proxy server.
     */
    open func stop() {
        // Note it is not possible to close tunnel here since the tunnel dispatch queue is not available.
        // But just removing all of them is sufficient.
        tunnels.withBox {
            for tunnel in $0.value {
                tunnel.forceClose()
            }
//            $0.value.removeAll()
        }
        observer?.signal(.stopped(self))
    }

    /**
     Delegate method when the proxy server accepts a new ProxySocket from local.

     When implementing a concrete proxy server, e.g., HTTP proxy server, the server should listen on some port and then wrap the raw socket in a corresponding ProxySocket subclass, then call this method.

     - parameter socket: The accepted proxy socket.
     */
    func didAcceptNewSocket(_ socket: ProxySocket) {
        observer?.signal(.newSocketAccepted(socket, onServer: self))
        let tunnel = Tunnel(proxySocket: socket)
        tunnel.delegate = self
        tunnels.value.append(tunnel)
        tunnel.openTunnel()
    }

    // MARK: TunnelDelegate implemention

    /**
     Delegate method when a tunnel closed. The server will remote it internally.

     - parameter tunnel: The closed tunnel.
     */
    func tunnelDidClose(_ tunnel: Tunnel) {
        observer?.signal(.tunnelClosed(tunnel, onServer: self))
        tunnels.withBox { tunnels in
            guard let index = tunnels.value.index(of: tunnel) else {
                // things went strange
                return
            }
            tunnels.value.remove(at: index)
        }
    }
}
