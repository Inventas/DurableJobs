public protocol QueueSchedulingCoordinator: AnyObject, Sendable {
    func reconcile() async
}
