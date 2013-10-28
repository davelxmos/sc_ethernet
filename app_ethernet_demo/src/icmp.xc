#include <print.h>
#include <xclib.h>
#include <stdint.h>
#include "ethernet.h"

static unsigned short checksum_ip(const unsigned char frame[34])
{
  int i;
  unsigned accum = 0;

  for (i = 14; i < 34; i += 2)
  {
    accum += *((const uint16_t*)(frame + i));
  }

  // Fold carry into 16bits
  while (accum >> 16)
  {
    accum = (accum & 0xFFFF) + (accum >> 16);
  }

  accum = byterev(~accum) >> 16;

  return accum;
}


static int build_arp_response(unsigned char rxbuf[64],
                              unsigned char txbuf[64],
                              const unsigned char own_mac_addr[6],
                              const unsigned char own_ip_addr[4])
{
  unsigned word;
  unsigned char byte;

  for (int i = 0; i < 6; i++)
    {
      byte = rxbuf[22+i];
      txbuf[i] = byte;
      txbuf[32 + i] = byte;
    }
  word = (rxbuf, const unsigned[])[7];
  for (int i = 0; i < 4; i++)
    {
      txbuf[38 + i] = word & 0xFF;
      word >>= 8;
    }

  txbuf[28] = own_ip_addr[0];
  txbuf[29] = own_ip_addr[1];
  txbuf[30] = own_ip_addr[2];
  txbuf[31] = own_ip_addr[3];

  for (int i = 0; i < 6; i++)
  {
    txbuf[22 + i] = own_mac_addr[i];
    txbuf[6 + i] = own_mac_addr[i];
  }
  txbuf[12] = 0x08;
  txbuf[13] = 0x06;
  txbuf[14] = 0x00;
  txbuf[15] = 0x01;
  txbuf[16] = 0x08;
  txbuf[17] = 0x00;
  txbuf[18] = 0x06;
  txbuf[19] = 0x04;
  txbuf[20] = 0x00;
  txbuf[21] = 0x02;

  // Typically 48 bytes (94 for IPv6)
  for (int i = 42; i < 64; i++)
  {
    txbuf[i] = 0x00;
  }

  return 64;
}


static int is_valid_arp_packet(const unsigned char rxbuf[nbytes],
                               unsigned nbytes,
                               const unsigned char own_ip_addr[4])
{
  if (rxbuf[12] != 0x08 || rxbuf[13] != 0x06)
    return 0;

  printstr("ARP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x01000608)
  {
    printstr("Invalid et_htype\n");
    return 0;
  }
  if ((rxbuf, const unsigned[])[4] != 0x04060008)
  {
    printstr("Invalid ptype_hlen\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[5] & 0xFFFF) != 0x0100)
  {
    printstr("Not a request\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[38 + i] != own_ip_addr[i])
    {
      printstr("Not for us\n");
      return 0;
    }
  }

  return 1;
}


static int build_icmp_response(unsigned char rxbuf[], unsigned char txbuf[],
                               const unsigned char own_mac_addr[6],
                               const unsigned char own_ip_addr[4])
{
  unsigned icmp_checksum;
  int datalen;
  int totallen;
  const int ttl = 0x40;
  int pad;

  // Precomputed empty IP header checksum (inverted, bytereversed and shifted right)
  unsigned ip_checksum = 0x0185;

  for (int i = 0; i < 6; i++)
    {
      txbuf[i] = rxbuf[6 + i];
    }
  for (int i = 0; i < 4; i++)
    {
      txbuf[30 + i] = rxbuf[26 + i];
    }
  icmp_checksum = byterev((rxbuf, const unsigned[])[9]) >> 16;
  for (int i = 0; i < 4; i++)
    {
      txbuf[38 + i] = rxbuf[38 + i];
    }
  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  datalen = totallen - 28;
  for (int i = 0; i < datalen; i++)
    {
      txbuf[42 + i] = rxbuf[42+i];
    }

  for (int i = 0; i < 6; i++)
  {
    txbuf[6 + i] = own_mac_addr[i];
  }
  (txbuf, unsigned[])[3] = 0x00450008;
  totallen = byterev(28 + datalen) >> 16;
  (txbuf, unsigned[])[4] = totallen;
  ip_checksum += totallen;
  (txbuf, unsigned[])[5] = 0x01000000 | (ttl << 16);
  (txbuf, unsigned[])[6] = 0;
  for (int i = 0; i < 4; i++)
  {
    txbuf[26 + i] = own_ip_addr[i];
  }
  ip_checksum += (own_ip_addr[0] | own_ip_addr[1] << 8);
  ip_checksum += (own_ip_addr[2] | own_ip_addr[3] << 8);
  ip_checksum += txbuf[30] | (txbuf[31] << 8);
  ip_checksum += txbuf[32] | (txbuf[33] << 8);

  txbuf[34] = 0x00;
  txbuf[35] = 0x00;

  icmp_checksum = (icmp_checksum + 0x0800);
  icmp_checksum += icmp_checksum >> 16;
  txbuf[36] = icmp_checksum >> 8;
  txbuf[37] = icmp_checksum & 0xFF;

  while (ip_checksum >> 16)
  {
    ip_checksum = (ip_checksum & 0xFFFF) + (ip_checksum >> 16);
  }
  ip_checksum = byterev(~ip_checksum) >> 16;
  txbuf[24] = ip_checksum >> 8;
  txbuf[25] = ip_checksum & 0xFF;

  for (pad = 42 + datalen; pad < 64; pad++)
  {
    txbuf[pad] = 0x00;
  }
  return pad;
}


static int is_valid_icmp_packet(const unsigned char rxbuf[nbytes],
                                unsigned nbytes,
                                const unsigned char own_ip_addr[4])
{
  unsigned totallen;
  if (rxbuf[23] != 0x01)
    return 0;

  printstr("ICMP packet received\n");

  if ((rxbuf, const unsigned[])[3] != 0x00450008)
  {
    printstr("Invalid et_ver_hdrl_tos\n");
    return 0;
  }
  if (((rxbuf, const unsigned[])[8] >> 16) != 0x0008)
  {
    printstr("Invalid type_code\n");
    return 0;
  }
  for (int i = 0; i < 4; i++)
  {
    if (rxbuf[30 + i] != own_ip_addr[i])
    {
      printstr("Not for us\n");
      return 0;
    }
  }

  totallen = byterev((rxbuf, const unsigned[])[4]) >> 16;
  if (nbytes > 60 && nbytes != totallen + 14)
  {
    printstr("Invalid size\n");
    printintln(nbytes);
    printintln(totallen+14);
    return 0;
  }
  if (checksum_ip(rxbuf) != 0)
  {
    printstr("Bad checksum\n");
    return 0;
  }

  return 1;
}

[[combinable]]
void icmp_server(client ethernet_if eth, const unsigned char ip_address[4])
{
  unsigned char mac_address[6];
  eth.get_macaddr(mac_address);
  eth.set_receive_filter_mask(0x1);
  printstr("Test started\n");

  while (1)
  {
    select {
    case eth.packet_ready():
      unsigned char rxbuf[ETHERNET_MAX_PACKET_SIZE];
      unsigned char txbuf[ETHERNET_MAX_PACKET_SIZE];
      ethernet_packet_info_t packet_info;
      eth.get_packet(packet_info, rxbuf, ETHERNET_MAX_PACKET_SIZE);

      if (is_valid_arp_packet(rxbuf, packet_info.len, ip_address))
      {
        int len = build_arp_response(rxbuf, txbuf, mac_address, ip_address);
        eth.send_packet(txbuf, len, ETHERNET_ALL_INTERFACES);
        printstr("ARP response sent\n");
      }
      else if (is_valid_icmp_packet(rxbuf, packet_info.len, ip_address))
      {
        int len = build_icmp_response(rxbuf, txbuf, mac_address, ip_address);
        eth.send_packet(txbuf, len, ETHERNET_ALL_INTERFACES);
        printstr("ICMP response sent\n");
      }
      break;
    }
  }
}

