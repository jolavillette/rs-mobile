package cc.retroshare.retroshare

/**
 * The local port of this application's core (its JSON API on 127.0.0.1).
 * The one place to change it on Android: the service starts the core on it
 * and the interface asks for it through the "jsonApiPort" call. Two
 * applications built from this code must not share it, or the interface of
 * one would drive the core of the other.
 */
object CorePort {
    const val JSON_API = 9092
}
