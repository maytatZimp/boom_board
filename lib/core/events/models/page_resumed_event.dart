/// The browser page came back on screen after having been hidden.
///
/// Distinct from [SocketConnectedEvent]: a short background does not
/// necessarily drop the socket, so this can fire with no reconnect at all --
/// which is exactly the case that would otherwise leave the client running on
/// stale state with nothing to correct it.
class PageResumedEvent {}
