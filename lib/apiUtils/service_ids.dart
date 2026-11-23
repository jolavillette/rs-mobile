/// The core keys service permissions (rsServiceControl) by the full service
/// id: the packet version (0x02) in the top byte and the 16-bit service type
/// under it, as RsServiceInfo::RsServiceInfoUIn16ToFullServiceId() builds it.
/// A bare service type such as 0x0215 matches no service there.
int rsFullServiceId(int serviceType) => (0x02 << 24) | (serviceType << 8);

/// 16-bit service types (RsServiceType in the core).
abstract final class RsServiceTypes {
  static const int messages = 0x0013;
  static const int globalRouter = 0x0018;
  static const int fileDatabase = 0x0019;
  static const int forums = 0x0215;
  static const int boards = 0x0216;
  static const int channels = 0x0217;
  static const int circles = 0x0218;
  static const int calendar = 0x0221;
  static const int gxsMails = 0x0230;
}
