import Foundation
import NearbyInteraction

protocol NearbySessionManagerDelegate: AnyObject {
    func didUpdateDistance(_ distance: Float)
}

class NearbySessionManager: NSObject, NISessionDelegate {
    var session: NISession?
    weak var delegate: NearbySessionManagerDelegate?

    override init() {
        super.init()
        session = NISession()
        session?.delegate = self
    }

    func runPeerSession(peerToken: NIDiscoveryToken) {
        guard NISession.isSupported else {
            print("Nearby Interaction not supported on this device")
            return
        }
        let config = NINearbyPeerConfiguration(peerToken: peerToken)
        session?.run(config)
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let object = nearbyObjects.first,
              let distance = object.distance else { return }

        delegate?.didUpdateDistance(Float(distance))
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        print("Nearby session invalidated: \(error.localizedDescription)")
    }
}
