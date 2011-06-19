function FindProxyForURL(url, host)
{
    var POLIPO_PROXY = "PROXY 127.0.0.1:8123";
    var DIRECT = "DIRECT";

    if (isPlainHostName(host)) // ホスト名にピリオドが含まれているかどうか
       return DIRECT;

    if (url.substring(0, 4) == "ftp:") // FTPプロトコル
       return DIRECT;

    if (dnsDomainIs(host, "2ch.net")) // 2ch.netドメインは直接接続する
       return DIRECT;

    if (localHostOrDomainIs(host, "idisk.mac.com")) // idisk.mac.comは直接接続する
       return DIRECT;

    if (isInNet(host, "10.0.0.0", "255.0.0.0") ||
        isInNet(host, "127.0.0.0", "255.0.0.0") ||
        isInNet(host, "169.254.0.0", "255.255.0.0") ||
        isInNet(host, "192.168.0.0", "255.255.0.0")
      ) { return DIRECT; } // ローカルネットワーク時は、Proxyサーバーを利用する

      return POLIPO_PROXY; // POLIPOを使用する
}

