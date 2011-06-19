function FindProxyForURL(url, host)
{
  var DIRECT = "DIRECT";

  // 192.168.168.* ネットワークのときは、
  // SOCKS経由でアクセスするようにする。
  if (isInNet(host, "192.168.168.0", "255.255.255.0")){
    return "SOCKS 192.168.1.52:11111";
  }

  return DIRECT;
}
