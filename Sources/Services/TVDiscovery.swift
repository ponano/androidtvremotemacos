import Cocoa
import Foundation
import AppKit
import Network
import ServiceManagement
import Speech
import AVFoundation
import Darwin

class TVDiscovery: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browser: NetServiceBrowser?
    private var discoveredServices = [NetService]()
    var onTVFound: ((String) -> Void)?
    var onSearchFailed: (() -> Void)?
    
    func startSearch() {
        print("[Bonjour] Starting search for _androidtvremote2._tcp...")
        discoveredServices.removeAll()
        browser = NetServiceBrowser()
        browser?.delegate = self
        browser?.searchForServices(ofType: "_androidtvremote2._tcp", inDomain: "local.")
    }
    
    func stopSearch() {
        browser?.stop()
        browser = nil
        for service in discoveredServices {
            service.stop()
        }
        discoveredServices.removeAll()
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        print("[Bonjour] Discovered service: \(service.name)")
        discoveredServices.append(service)
        service.delegate = self
        service.resolve(withTimeout: 5.0)
    }
    
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard let addresses = sender.addresses, !addresses.isEmpty else {
            print("[Bonjour] Service resolved but has no addresses.")
            return
        }
        
        for address in addresses {
            address.withUnsafeBytes { ptr in
                guard let addr = ptr.baseAddress?.assumingMemoryBound(to: sockaddr.self) else { return }
                if addr.pointee.sa_family == AF_INET {
                    let addrIn = ptr.baseAddress?.assumingMemoryBound(to: sockaddr_in.self)
                    var ipBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    var sin_addr = addrIn!.pointee.sin_addr
                    if let ipStr = inet_ntop(AF_INET, &sin_addr, &ipBuffer, socklen_t(INET_ADDRSTRLEN)) {
                        let ip = String(cString: ipStr)
                        print("[Bonjour] Resolved IPv4: \(ip)")
                        self.stopSearch()
                        DispatchQueue.main.async {
                            self.onTVFound?(ip)
                        }
                    }
                }
            }
        }
    }
    
    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String : NSNumber]) {
        print("[Bonjour Error] Search failed: \(errorDict)")
        DispatchQueue.main.async {
            self.onSearchFailed?()
        }
    }
    
    func netService(_ sender: NetService, didNotResolve errorDict: [String : NSNumber]) {
        print("[Bonjour Error] Resolve failed: \(errorDict)")
    }
}

