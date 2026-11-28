/// The core keys service permissions (rsServiceControl) by the full service
/// id: the packet version (0x02) in the top byte and the 16-bit service type
/// under it, as RsServiceInfo::RsServiceInfoUIn16ToFullServiceId() builds it.
/// A bare service type such as 0x0215 matches no service there.
int rsFullServiceId(int serviceType) => (0x02 << 24) | (serviceType << 8);

/// The 16-bit service type of a full service id.
int rsServiceType(int fullServiceId) => (fullServiceId >> 8) & 0xffff;

/// 16-bit service types (RsServiceType in the core).
abstract final class RsServiceTypes {
  static const int discovery = 0x0011;
  static const int chat = 0x0012;
  static const int messages = 0x0013;
  static const int turtle = 0x0014;
  static const int heartbeat = 0x0016;
  static const int fileTransfer = 0x0017;
  static const int globalRouter = 0x0018;
  static const int fileDatabase = 0x0019;
  static const int serviceInfo = 0x0020;
  static const int bandwidthControl = 0x0021;
  static const int gxsTunnels = 0x0028;
  static const int mobileLink = 0x0029;
  static const int banList = 0x0101;
  static const int status = 0x0102;
  static const int identities = 0x0211;
  static const int forums = 0x0215;
  static const int boards = 0x0216;
  static const int channels = 0x0217;
  static const int circles = 0x0218;
  static const int reputation = 0x0219;
  static const int calendar = 0x0221;
  static const int gxsMails = 0x0230;
  static const int rtt = 0x1011;
}
