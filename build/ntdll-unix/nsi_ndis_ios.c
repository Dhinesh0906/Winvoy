/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright 2026 125hz
 * Madeira Converter Exception: see LICENSE-EXCEPTION.md
 *
 * iOS-Madeira: Wine's BSD network-interface provider for the in-process NSI.
 *
 * Compiles wine/dlls/nsiproxy.sys/ndis.c unchanged (LGPL-2.1-or-later; its
 * authors' notice is in that file) for the iOS ntdll unix library; see
 * nsi_network_ios.c. The iPhoneOS SDK omits <net/if_arp.h>,
 * <netinet/if_ether.h>, <netinet/ip_var.h> and <netinet/icmp_var.h>, which
 * the macOS config.h announces, so those HAVE_* macros are dropped and
 * ndis.c takes its portable paths. if_nameindex, the interface ioctls and
 * the NET_RT_IFLIST sysctl it uses are all available; the routing-message
 * declarations come from shims/net/route.h. */
#include "config.h"
#undef HAVE_NET_IF_ARP_H
#undef HAVE_NETINET_IF_ETHER_H
#undef HAVE_NETINET_IP_VAR_H
#undef HAVE_NETINET_ICMP_VAR_H
#include "../../wine/dlls/nsiproxy.sys/ndis.c"
