/* $Id: transport_adapter_sample.c 5478 2016-11-03 09:39:20Z riza $ */
/*
 * Copyright (C) 2008-2011 Teluu Inc. (http://www.teluu.com)
 * Copyright (C) 2003-2008 Benny Prijono <benny@prijono.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */

//#include <pjmedia/stream.h>
#include <pjmedia/vid_stream.h>
#include <pj/assert.h>
#include <pj/pool.h>
#include <pj/log.h>
#include "transport_adapter_fec.h"
#include <time.h>
#include <pjmedia/rtp.h>

//#pragma comment(lib, "openfec.lib")

/* Fast floor/ceiling macro-functions
 * https://www.codeproject.com/Tips/700780/Fast-floor-ceiling-functions
 */
#define shift_floor(arg)    ((int)(arg + 32768.) - 32768)
#define shift_ceil(arg)        (32768 - (int)(32768. - arg))

/*
 * Redundancy parameters DEFAULT_K, DEFAULT_N
 * CODE_RATE only for dynamic memory allocation (n = k / code_rate)
 * Change if required
 */

/*
 * Size must be multiple 32bit
 */
typedef struct fec_ext_hdr
{
    
    pj_uint32_t                sn;                        /* Symbol sequence number (ecnoding block number) */
    pj_uint16_t                esi;                    /* Encoding symbol ID */
    pj_uint16_t                k;                        /* Source symbols in block */
    pj_uint16_t                n;                        /* Source+repair symbols in block */
    pj_uint16_t                len;                    /* Real symbol size in block for repair */
} fec_ext_hdr;

#define K_MAX 20 /* Source symbols max count in sequence */
/* Symbol size, in bytes. Reserved place for ESI and sequence number */
#define SYMBOL_SIZE_MAX    (PJMEDIA_MAX_VID_PAYLOAD_SIZE - sizeof(fec_ext_hdr) - sizeof(pjmedia_rtp_ext_hdr) - sizeof(pjmedia_rtp_hdr))
#define CODE_RATE    0.667                                                    /* k/n = 2/3 means we add 50% of repair symbols. Use DEFAULT_N instead */
#define N_MAX        shift_ceil(K_MAX / CODE_RATE)                        /* n value = k/code_rate means we add 20% of repair symbols */
#define RTP_VERSION 2

/* For logging purpose. */
#define THIS_FILE   "adap_openfec"

/* Encoding buffers. We'll update it progressively */
static void*        enc_symbols_ptr[N_MAX];                    /* Table containing pointers to the encoding (i.e. source + repair) symbols buffers */
static char            enc_symbols_buf[SYMBOL_SIZE_MAX * N_MAX];    /* Buffer containing encoding (i.e. source + repair) symbols */
static pj_uint32_t    enc_symbols_size[N_MAX];                /* Table containing network(real) sizes of the encoding symbols(packets) (i.e. source + repair) */
static pj_uint8_t    enc_symbol_buf[SYMBOL_SIZE_MAX + sizeof(fec_ext_hdr) + sizeof(pjmedia_rtp_ext_hdr) + sizeof(pjmedia_rtp_hdr)];

/* Decoding buffers. We'll update it progressively */
static void*        dec_symbols_ptr[N_MAX];                    /* Table containing pointers to the decoding (i.e. source + repair) symbols buffers */
static char            dec_symbols_buf[SYMBOL_SIZE_MAX * N_MAX];    /* Buffer containing decoding (i.e. source + repair) symbols */
static pj_uint32_t    dec_symbols_size[N_MAX];                /* Table containing network(real) sizes of the decoding symbols(packets) (i.e. source + repair) */

/* Transport functions prototypes */
static pj_status_t    transport_get_info        (pjmedia_transport *tp, pjmedia_transport_info *info);
static pj_status_t    transport_attach        (pjmedia_transport *tp,    void *user_data, const pj_sockaddr_t *rem_addr,    const pj_sockaddr_t *rem_rtcp, unsigned addr_len, void(*rtp_cb)(void*, void*, pj_ssize_t), void(*rtcp_cb)(void*, void*, pj_ssize_t));
#if defined(PJ_VERSION_NUM_MAJOR) && (PJ_VERSION_NUM_MAJOR == 2) && defined(PJ_VERSION_NUM_MINOR) && (PJ_VERSION_NUM_MINOR >= 6)
static pj_status_t    transport_attach2        (pjmedia_transport *tp, pjmedia_transport_attach_param *att_prm);
#endif
static void            transport_detach        (pjmedia_transport *tp, void *strm);
static pj_status_t    transport_send_rtp        (pjmedia_transport *tp, const void *pkt, pj_size_t size);
static pj_status_t    transport_send_rtcp        (pjmedia_transport *tp, const void *pkt, pj_size_t size);
static pj_status_t    transport_send_rtcp2    (pjmedia_transport *tp, const pj_sockaddr_t *addr, unsigned addr_len, const void *pkt, pj_size_t size);
static pj_status_t    transport_media_create    (pjmedia_transport *tp, pj_pool_t *sdp_pool, unsigned options, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t    transport_encode_sdp    (pjmedia_transport *tp, pj_pool_t *sdp_pool, pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t    transport_media_start    (pjmedia_transport *tp, pj_pool_t *pool, const pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t    transport_media_stop    (pjmedia_transport *tp);
static pj_status_t    transport_simulate_lost    (pjmedia_transport *tp, pjmedia_dir dir, unsigned pct_lost);
static pj_status_t    transport_destroy        (pjmedia_transport *tp);

/* FEC functions prototypes */
/* Decoder callback for source and repair restored symbols */
static void*        fec_dec_cb                (void *context /* TP adapter */, pj_uint32_t size, pj_uint32_t esi);
/* Decode from RTP packet FEC extension header */
static void*        fec_dec_hdr                (const void *pkt, fec_ext_hdr *fec_hdr);
/* Decode source and repair symbols */
static pj_uint32_t    fec_dec_pkt                (void * const dst, void *pkt, pj_uint32_t size, pj_bool_t rtp);
/* Init decoder instance with new params */
static pj_status_t    fec_dec_init            (void *user_data, unsigned k, unsigned n, unsigned len);

/* Add packets to buffer and call encoder */
static pj_status_t    fec_enc_pkt                (void *user_data /* TP adapter */, const void *pkt, pj_size_t size);
/* Add FEC extension header to sources packets before send */
static pj_uint16_t    fec_enc_src                (void *dst, const void *pkt, pj_uint32_t size, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr);
/* Add RTP and FEC extension headers to repair packets before send */
static pj_uint16_t  fec_enc_rpr                (void *dst, pjmedia_rtp_session *ses, int ts_len, const void *payload, pj_uint32_t payload_len, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr);
/* Clear adapter encoding buffers */
static pj_status_t    fec_enc_reset            (void *user_data, unsigned n, unsigned len);

/* The transport operations */
static struct pjmedia_transport_op tp_adapter_op =
{
    &transport_get_info,
#if defined(PJ_VERSION_NUM_MAJOR) && (PJ_VERSION_NUM_MAJOR == 2) && defined(PJ_VERSION_NUM_MINOR) && (PJ_VERSION_NUM_MINOR <= 6)
    &transport_attach,
#else
    NULL,
#endif
    &transport_detach,
    &transport_send_rtp,
    &transport_send_rtcp,
    &transport_send_rtcp2,
    &transport_media_create,
    &transport_encode_sdp,
    &transport_media_start,
    &transport_media_stop,
    &transport_simulate_lost,
    &transport_destroy,
#if defined(PJ_VERSION_NUM_MAJOR) && (PJ_VERSION_NUM_MAJOR == 2) && defined(PJ_VERSION_NUM_MINOR) && (PJ_VERSION_NUM_MINOR >= 6)
    &transport_attach2,
#endif
};

/* The transport adapter instance */
struct tp_adapter
{
    pjmedia_transport    base;
    pj_bool_t            del_base;
    pj_pool_t            *pool;
    
    /* Stream information. */
    void                *stream_user_data;
    void                *stream_ref;
    void                (*stream_rtp_cb)(void *user_data, void *pkt, pj_ssize_t);
    void                (*stream_rtcp_cb)(void *user_data, void *pkt, pj_ssize_t);
    
    
    pjmedia_transport        *slave_tp;                    /* Base transport pointer */
    
    /* FEC specific encoding/decoding members */
    of_codec_id_t            codec_id;                    /* Identifier of the codec to use */
    
    of_session_t            *dec_ses;                    /* openfec decoder instance identifier */
    
    of_parameters_t            *enc_params;                /* Pointer to common encoding params */
    of_parameters_t            *dec_params;                /* Pointer to common decoding params */
    
    of_rs_2_m_parameters_t    enc_rs_params;                /* Structure used to store Reed-Solomon codes over GF(2^m) params */
    of_ldpc_parameters_t    enc_ldps_params;            /* Structure used to store LDPC-Staircase large block FEC codes params */
    
    of_rs_2_m_parameters_t    dec_rs_params;                /* Structure used to store Reed-Solomon codes over GF(2^m) params */
    of_ldpc_parameters_t    dec_ldps_params;            /* Structure used to store LDPC-Staircase large block FEC codes params */
    
    //pjmedia_stream_rtp_sess_info rtp_ses_info;
    pjmedia_rtp_session        *rtp_tx_ses;                /* Pointer to encoding RTP session */
    
    pjmedia_rtp_hdr            rtp_hdr;                    /* RTP header with common default values for encoding repair symbols */
    pjmedia_rtp_ext_hdr        ext_hdr;                    /* RTP Extension header with common default values for encoding purpose */
    fec_ext_hdr                fec_hdr;                    /* RTP Extension header data with common FEC encoding session values */
    
    /* FEC specific runtime values */
    pj_uint32_t                snd_k;                        /* Current number of ready to send source symbols in the block */
    pj_uint32_t                snd_sn;                        /* Current number of encoding symbol's sequence */
    pj_uint32_t                snd_len;                    /* Current packet max length of encoding symbol's sequence */
    pj_bool_t                snd_ready;
    
    pj_uint32_t                rcv_k;                        /* Current number of recieved source/repair symbols in the block */
    pj_uint32_t                rcv_sn;                        /* Current number of decoding symbol's sequence */
    pj_uint32_t                rcv_len;                    /* Current packet max length of decoding symbol's sequence */
    pj_bool_t                rcv_ready;
};

/**
 * Dumps len32 32-bit words of a buffer (typically a symbol).
 */
static void dump_pkt(const void *buf, const pj_uint32_t size, pj_uint32_t esi, const char *type)
{
    char    *ptr;
    pj_uint32_t    n = size;
    char str[SYMBOL_SIZE_MAX * 3] = { '\0' }, *p = str;
    
    p += sprintf(p, "%s_%03u size=%u: ", type, esi, size);
    p += sprintf(p, "0x");
    for (ptr = (char *)buf; n > 0; n--, ptr++)
    {
        p += sprintf(p, "%hhX", *ptr);
    }
    p += sprintf(p, "\n");
    
    PJ_LOG(4, (THIS_FILE, str));
}

/* Clear runtime params and encoding buffer */
static pj_status_t fec_enc_reset(void *user_data, unsigned n, unsigned len)
{
    struct tp_adapter *adapter = (struct tp_adapter *)user_data;
    pj_uint32_t esi;
    
    if (!adapter)
        return PJ_EINVAL;
    
    /* Clear buffer */
    for (esi = 0; esi < n; esi++)
    {
        memset(enc_symbols_ptr[esi], 0, len);
        enc_symbols_size[esi] = 0;
    }
    
    /* Reset runtime params */
    adapter->snd_k = 0;
    adapter->snd_len = 0;
    adapter->snd_ready = PJ_FALSE;
    
    return PJ_SUCCESS;
}

/* New decoder creation for adaptive decoding */
static pj_status_t fec_dec_init(void *user_data, unsigned k, unsigned n, unsigned len)
{
    struct tp_adapter *adapter = (struct tp_adapter *)user_data;
    pj_status_t status = PJ_SUCCESS;
    pj_uint32_t esi;
    
    if (!adapter)
        return PJ_EINVAL;
    
    /* Decoder reinit */
    if (adapter->dec_ses)
        of_release_codec_instance(adapter->dec_ses);
    
    for (esi = 0; esi < n; esi++)
    {
        memset(dec_symbols_ptr[esi], 0, len);
        dec_symbols_size[esi] = 0;
    }
    
    adapter->rcv_k = 0;
    adapter->dec_params->nb_source_symbols = k;
    adapter->dec_params->nb_repair_symbols = n - k;
    adapter->dec_params->encoding_symbol_length = len;
    
    /* Open and initialize the openfec session */
    if (of_create_codec_instance(&adapter->dec_ses, adapter->codec_id, OF_DECODER, 2 /* Verbosity */) != OF_STATUS_OK)
    {
        status = PJ_EINVAL;
        PJ_LOG(4, (THIS_FILE, "Create decoder instance failed"));
    }
    /* Set session parameters */
    if (status == PJ_SUCCESS && of_set_fec_parameters(adapter->dec_ses, adapter->dec_params) != OF_STATUS_OK)
    {
        status = PJ_EINVAL;
        PJ_LOG(4, (THIS_FILE, "Set parameters failed for decoder codec_id=%d", adapter->codec_id));
    }
    
    /* Setup callbacks for decoding */
    if (of_set_callback_functions(adapter->dec_ses, fec_dec_cb, NULL, adapter) != OF_STATUS_OK)
    {
        status = PJ_EINVAL;
        PJ_LOG(4, (THIS_FILE, "Set callback functions failed for decoder with codec_id=%d", adapter->codec_id));
    }
    
    
    /* Cleanup session on fail */
    if (status != PJ_SUCCESS && adapter->dec_ses)
        of_release_codec_instance(adapter->dec_ses);
    
    return status;
}

static pj_status_t fec_enc_pkt(void *user_data, const void *pkt, pj_size_t size)
{
    struct tp_adapter    *adapter = (struct tp_adapter *)user_data;
    pj_status_t            status = PJ_SUCCESS;
    pj_uint32_t            esi;
    pj_uint32_t            n, k, len;
    of_session_t        *ses;
    
    if (!adapter || !pkt)
        return PJ_EINVAL;
    
    /* Put to table only if current count of symbols less than k */
    if (adapter->snd_k < K_MAX)
    {
        /* Copy source symbol to buffer */
        memcpy(enc_symbols_ptr[adapter->snd_k], pkt, size);
        
        /* Remember real size for source symbols */
        enc_symbols_size[adapter->snd_k] = size;
        
        adapter->snd_k++;
        
        /* Update max packet length in sequence */
        if (size > adapter->snd_len)
            adapter->snd_len = size;
    }
    
    pjmedia_rtp_hdr * rtp_hdr = (pjmedia_rtp_hdr *)pkt;
    
    if (adapter->snd_k < K_MAX && !rtp_hdr->m)
        return PJ_SUCCESS;
    
    /*
     * If symboil is key frame or collected count equal max value,
     * stop collect source symbols, build repair and send
     */
    
    k = adapter->snd_k;
    n = shift_ceil(k / CODE_RATE);
    len = adapter->snd_len;
    
    /* Sequence counter for symbols block */
    adapter->snd_sn++;
    
    /* Setup current encoder params */
    adapter->enc_params->nb_source_symbols = k;
    adapter->enc_params->nb_repair_symbols = n - k;
    adapter->enc_params->encoding_symbol_length = len;
    
    /* Open and initialize the openfec session */
    if (of_create_codec_instance(&ses, adapter->codec_id, OF_ENCODER, 2 /* Verbosity */) != OF_STATUS_OK)
    {
        PJ_LOG(4, (THIS_FILE, "Create encoder instance failed"));
        
        return PJ_EINVAL;
    }
    
    /* Set session parameters */
    if (of_set_fec_parameters(ses, adapter->enc_params) != OF_STATUS_OK)
    {
        PJ_LOG(4, (THIS_FILE, "Set parameters failed for encoder codec_id=%d", adapter->codec_id));
        
        /* Cleanup session on fail before return */
        of_release_codec_instance(ses);
        
        return PJ_EINVAL;
    }
    
    /* Build the n-k repair symbols if count of symbols is enough */
    for (esi = k; esi < n; esi++)
    {
        if (of_build_repair_symbol(ses, enc_symbols_ptr, esi) != OF_STATUS_OK)
        {
            PJ_LOG(4, (THIS_FILE, "Build repair symbol failed for esi=%u", esi));
        }
        else
        {
            /* Set repair symbol length to max value */
            enc_symbols_size[esi] = len;
        }
    }
    
    adapter->snd_ready = PJ_TRUE;
    
    /* Cleanup session on fail and success */
    of_release_codec_instance(ses);
    
    return status;
}

/* Single restore callback for source and repair packets */
static void* fec_dec_cb(void *context, pj_uint32_t size, pj_uint32_t esi)
{
    /* Must return buffer pointer for decoder to save restored source packet in adapter buffer */
    return dec_symbols_ptr[esi];
}

/* Construct in destination buffer packet with Extension header and data based on original RTP source symbol */
static pj_uint16_t fec_enc_src(void *dst, const void *pkt, pj_uint32_t size, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr)
{
    unsigned num;
    pj_uint8_t *ptr = (pj_uint8_t *)dst;
    
    /* Assume RTP header at begin of packet */
    pjmedia_rtp_hdr *rtp_hdr = (pjmedia_rtp_hdr *)pkt;
    
    /* Sanity check */
    if (rtp_hdr->v != RTP_VERSION || rtp_hdr->x)
    {
        PJ_LOG(4, (THIS_FILE, "RTP packet header decode failed esi=%u, sn=%u", fec_hdr->esi, fec_hdr->sn));
        return 0;
    }
    
    /* Set Extension header flag in original RTP packet */
    rtp_hdr->x = 1;
    
    /* Payload is located right after header plus CSRC */
    /* Copy modified header plus CSRCs until payload */
    num = sizeof(pjmedia_rtp_hdr) + rtp_hdr->cc * sizeof(pj_uint32_t);
    memcpy(ptr, pkt, num);
    ptr += num;
    
    /* Remember payload offset in original packet and decrease copy left size */
    //(pj_uint8_t *)pkt += num;
    pkt = (pj_uint8_t *)pkt + num;
    size -= num;
    
    /* Insert RTP Extension header */
    num = sizeof(pjmedia_rtp_ext_hdr);
    memcpy(ptr, ext_hdr, num);
    ptr += num;
    
    /* Insert FEC header as Extension header data */
    num = sizeof(fec_ext_hdr);
    memcpy(ptr, fec_hdr, num);
    ptr += num;
    
    /* Copy payload */
    memcpy(ptr, pkt, size);
    ptr += size;
    
    return (ptr - (pj_uint8_t *)dst);
}

/* Construct in destination buffer RTP packet with Extension header and data based on FEC repair symbol */
static pj_uint16_t fec_enc_rpr(void *dst, pjmedia_rtp_session *ses, int ts_len, const void *payload, pj_uint32_t payload_len, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr)
{
    int num;
    pj_uint8_t *ptr = (pj_uint8_t *)dst;
    pjmedia_rtp_hdr *hdr;
    
    /* Get RTP header */
    //rtp_hdr = (pjmedia_rtp_hdr *)hdr;
    pjmedia_rtp_encode_rtp(ses, ses->out_pt, 0, payload_len, ts_len, &hdr, &num);
    
    /* Copy RTP header */
    //num = sizeof(pjmedia_rtp_hdr) + rtp_hdr->cc * sizeof(pj_uint32_t);
    memcpy(ptr, hdr, num);
    ((pjmedia_rtp_hdr *)dst)->x = 1;
    ptr += num;
    
    /* Copy RTP Extension header */
    num = sizeof(pjmedia_rtp_ext_hdr);
    memcpy(ptr, ext_hdr, num);
    ptr += num;
    
    /* Copy FEC header as Extension header data */
    num = sizeof(fec_ext_hdr);
    memcpy(ptr, fec_hdr, num);
    ptr += num;
    
    /* Copy repair symbol */
    memcpy(ptr, payload, payload_len);
    ptr += payload_len;
    
    return (ptr - (pj_uint8_t *)dst);
}

static void* fec_dec_hdr(const void *pkt, fec_ext_hdr *fec_hdr)
{
    unsigned num;
    pj_uint8_t *ptr = (pj_uint8_t *)pkt;
    
    /* Assume RTP header at begin of packet */
    pjmedia_rtp_hdr *rtp_hdr = (pjmedia_rtp_hdr *)pkt;
    
    pj_assert(rtp_hdr->v == RTP_VERSION);
    
    /* Sanity check */
    if (rtp_hdr->v != RTP_VERSION)
    {
        PJ_LOG(4, (THIS_FILE, "FEC header in RTP packet decode failed"));
        return 0;
    }
    
    /* FEC header is located right after RTP header + CSRCs + Extension header */
    num = sizeof(pjmedia_rtp_hdr) + rtp_hdr->cc * sizeof(pj_uint32_t) + sizeof(pjmedia_rtp_ext_hdr);
    ptr += num;
    
    fec_hdr->sn = pj_ntohl(*(pj_uint32_t *)ptr);
    ptr += sizeof(pj_uint32_t);
    fec_hdr->esi = pj_ntohs(*(pj_uint16_t *)ptr);
    ptr += sizeof(pj_uint16_t);
    fec_hdr->k = pj_ntohs(*(pj_uint16_t *)ptr);
    ptr += sizeof(pj_uint16_t);
    fec_hdr->n = pj_ntohs(*(pj_uint16_t *)ptr);
    ptr += sizeof(pj_uint16_t);
    fec_hdr->len = pj_ntohs(*(pj_uint16_t *)ptr);
    ptr += sizeof(pj_uint16_t);
    
    return ptr;
}

static pj_uint32_t fec_dec_pkt(void * const dst, void *pkt, pj_uint32_t size, pj_bool_t rtp)
{
    unsigned num;
    pj_uint8_t *ptr = (pj_uint8_t *)dst;
    pjmedia_rtp_hdr *rtp_hdr = (pjmedia_rtp_hdr *)pkt;
    
    pj_assert(rtp_hdr->v == RTP_VERSION);
    
    /* Size of RTP header plus CSRCs until Extension header */
    num = sizeof(pjmedia_rtp_hdr) + rtp_hdr->cc * sizeof(pj_uint32_t);
    
    /* Copy RTP header if source symbol */
    if (rtp)
    {
        rtp_hdr->x = 0;
        
        memcpy(ptr, pkt, num);
        ptr += num;
    }
    
    /* Skip Extension header and data */
    num += sizeof(pjmedia_rtp_ext_hdr);
    num += sizeof(fec_ext_hdr);
    
    /* Set payload offset in original packet and decrease copy left size */
    //(pj_uint8_t *)pkt += num;
    pkt = (pj_uint8_t *)pkt + num;
    size -= num;
    
    memcpy(ptr, pkt, size);
    ptr += size;
    
    return (ptr - (pj_uint8_t *)dst);
}

/*
 * Create the adapter.
 */
PJ_DEF(pj_status_t) pjmedia_fec_adapter_create(pjmedia_endpt *endpt, const char *name, pjmedia_transport *transport, pj_bool_t del_base, pjmedia_transport **p_tp)
{
    pj_pool_t *pool;
    struct tp_adapter *adapter;
    
    if (name == NULL)
        name = "tpad%p";
    
    /* Create the pool and initialize the adapter structure */
    pool = pjmedia_endpt_create_pool(endpt, name, 512, 512);
    adapter = PJ_POOL_ZALLOC_T(pool, struct tp_adapter);
    adapter->pool = pool;
    pj_ansi_strncpy(adapter->base.name, pool->obj_name, sizeof(adapter->base.name));
    adapter->base.type = (pjmedia_transport_type)(PJMEDIA_TRANSPORT_TYPE_USER + 1);
    adapter->base.op = &tp_adapter_op;
    
    /* Save the transport as the slave transport */
    adapter->slave_tp = transport;
    adapter->del_base = del_base;
    
    /* Done */
    *p_tp = &adapter->base;
    return PJ_SUCCESS;
}


/*
 * get_info() is called to get the transport addresses to be put
 * in SDP c= line and a=rtcp line.
 */
static pj_status_t transport_get_info(pjmedia_transport *tp, pjmedia_transport_info *info)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* Since we don't have our own connection here, we just pass
     * this function to the slave transport.
     */
    return pjmedia_transport_get_info(adapter->slave_tp, info);
}

/* Currently get packet real size, because openfec encode repair packet using size padding */
static pj_size_t fec_symbol_size(const void * const pkt, const pj_uint32_t symbol_size)
{
    /* Pointer to end of packet buffer */
    char *ptr = (char *)pkt + symbol_size - 1;
    pj_uint32_t size = symbol_size;
    
    while (!*ptr-- && size)
        --size;
    
    return size;
}

/* This is our RTP callback, that is called by the slave transport when it
 * receives RTP packet.
 */
static void transport_rtp_cb(void *user_data, void *pkt, pj_ssize_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter*)user_data;
    pj_uint16_t esi, k, len;
    fec_ext_hdr fec_hdr;
    
    adapter->rcv_k++;
    
    /* Decode FEC header before FEC decoding */
    fec_dec_hdr(pkt, &fec_hdr);
    
    /* Check packet FEC sequence number */
    if (fec_hdr.sn < adapter->rcv_sn)
    {
        PJ_LOG(4, (THIS_FILE, "Too late seq_num=%u received in a packet while decoder seq_num=%u, skip", fec_hdr.sn, adapter->rcv_sn));
        return;
    }
    /* New FEC sequence packet */
    else if (fec_hdr.sn > adapter->rcv_sn)
    {
        if (!of_is_decoding_complete(adapter->dec_ses))
        {
            PJ_LOG(4, (THIS_FILE, "Decoding incomplete for seq_num=%u, reset for new seq_num=%u", adapter->rcv_sn, fec_hdr.sn));
        }
        
        adapter->rcv_sn = fec_hdr.sn;
        /* Create new decoder session for new FEC sequence */
        fec_dec_init(adapter, fec_hdr.k, fec_hdr.n, fec_hdr.len);
    }
    /* Drop packet if sequence already decoded */
    else if (of_is_decoding_complete(adapter->dec_ses))
        return;
    
    /* Decode packet */
    size = fec_dec_pkt(dec_symbols_ptr[fec_hdr.esi], pkt, size, fec_hdr.esi < fec_hdr.k ? PJ_TRUE : PJ_FALSE);
    dec_symbols_size[fec_hdr.esi] = size;
    
    /*
     * Submit each fresh symbol to the library, upon reception
     * using the standard of_decode_with_new_symbol() function.
     */
    if (of_decode_with_new_symbol(adapter->dec_ses, dec_symbols_ptr[fec_hdr.esi], fec_hdr.esi) == OF_STATUS_ERROR)
        PJ_LOG(4, (THIS_FILE, "Decode with new symbol failed esi=%u, len=%u", fec_hdr.esi, adapter->dec_params->encoding_symbol_length));
    
    /* Exit if decoding not complete */
    if (!of_is_decoding_complete(adapter->dec_ses))
        return;
    
    //PJ_LOG(4, (THIS_FILE, "Decoded seq_num=%u", fec_hdr.sn));
    
    k = adapter->dec_params->nb_source_symbols;
    
    /* Call stream's callback for all source symbols in buffer */
    for (esi = 0; esi < k; esi++)
    {
        /* Get repaired packet real size */
        if (!dec_symbols_size[esi])
            dec_symbols_size[esi] = fec_symbol_size(dec_symbols_ptr[esi], adapter->dec_params->encoding_symbol_length);
        
        adapter->stream_rtp_cb(adapter->stream_user_data, dec_symbols_ptr[esi], dec_symbols_size[esi]);
    }
}

/* This is our RTCP callback, that is called by the slave transport when it
 * receives RTCP packet.
 */
static void transport_rtcp_cb(void *user_data, void *pkt, pj_ssize_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter*)user_data;
    
    pj_assert(adapter->stream_rtcp_cb != NULL);
    
    /* Call stream's callback */
    adapter->stream_rtcp_cb(adapter->stream_user_data, pkt, size);
}

#if defined(PJ_VERSION_NUM_MAJOR) && (PJ_VERSION_NUM_MAJOR == 2) && defined(PJ_VERSION_NUM_MINOR) && (PJ_VERSION_NUM_MINOR < 6)
/*
 * attach() needed only for old pjsip transport interfaces compatibility used in android client
 */
static pj_status_t transport_attach(pjmedia_transport *tp,
                                    void *user_data,
                                    const pj_sockaddr_t *rem_addr,
                                    const pj_sockaddr_t *rem_rtcp,
                                    unsigned addr_len,
                                    void(*rtp_cb)(void*, void*, pj_ssize_t),
                                    void(*rtcp_cb)(void*, void*, pj_ssize_t))
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    pj_status_t status;
    
    pj_assert(adapter->stream_user_data == NULL);
    adapter->stream_user_data = user_data;
    adapter->stream_rtp_cb = rtp_cb;
    adapter->stream_rtcp_cb = rtcp_cb;
    /* pjsip assign stream pointer to user_data  */
    adapter->stream_ref = user_data;
    
    /* Get pointer RTP session information of the media stream */
    pjmedia_vid_stream_get_rtp_session_tx(adapter->stream_ref, &adapter->rtp_tx_ses);
    
    rtp_cb = &transport_rtp_cb;
    rtcp_cb = &transport_rtcp_cb;
    user_data = adapter;
    
    status = pjmedia_transport_attach(adapter->slave_tp, user_data, rem_addr, rem_rtcp, addr_len, rtp_cb, rtcp_cb);
    if (status != PJ_SUCCESS)
    {
        adapter->stream_user_data = NULL;
        adapter->stream_rtp_cb = NULL;
        adapter->stream_rtcp_cb = NULL;
        adapter->stream_ref = NULL;
        return status;
    }
    
    return PJ_SUCCESS;
}
#endif

#if defined(PJ_VERSION_NUM_MAJOR) && (PJ_VERSION_NUM_MAJOR == 2) && defined(PJ_VERSION_NUM_MINOR) && (PJ_VERSION_NUM_MINOR >= 6)
/*
 * attach2() is called by stream to register callbacks that we should
 * call on receipt of RTP and RTCP packets.
 */
static pj_status_t transport_attach2(pjmedia_transport *tp, pjmedia_transport_attach_param *att_param)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    pj_status_t status;
    
    /* In this example, we will save the stream information and callbacks
     * to our structure, and we will register different RTP/RTCP callbacks
     * instead.
     */
    pj_assert(adapter->stream_user_data == NULL);
    adapter->stream_user_data = att_param->user_data;
    adapter->stream_rtp_cb = att_param->rtp_cb;
    adapter->stream_rtcp_cb = att_param->rtcp_cb;
    adapter->stream_ref = att_param->stream;
    
    /* Get pointer RTP session information of the media stream */
    pjmedia_stream_rtp_sess_info session_info;
    pjmedia_vid_stream_get_rtp_session_info(adapter->stream_ref, &session_info);
    adapter->rtp_tx_ses = session_info.tx_rtp;
    
    att_param->rtp_cb = &transport_rtp_cb;
    att_param->rtcp_cb = &transport_rtcp_cb;
    att_param->user_data = adapter;
    
    status = pjmedia_transport_attach2(adapter->slave_tp, att_param);
    if (status != PJ_SUCCESS)
    {
        adapter->stream_user_data = NULL;
        adapter->stream_rtp_cb = NULL;
        adapter->stream_rtcp_cb = NULL;
        adapter->stream_ref = NULL;
        return status;
    }
    
    return PJ_SUCCESS;
}
#endif

/*
 * detach() is called when the media is terminated, and the stream is
 * to be disconnected from us.
 */
static void transport_detach(pjmedia_transport *tp, void *strm)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    PJ_UNUSED_ARG(strm);
    
    if (adapter->stream_user_data != NULL)
    {
        pjmedia_transport_detach(adapter->slave_tp, adapter);
        adapter->stream_user_data = NULL;
        adapter->stream_rtp_cb = NULL;
        adapter->stream_rtcp_cb = NULL;
        adapter->stream_ref = NULL;
    }
}


/*
 * send_rtp() is called to send RTP packet. The "pkt" and "size" argument
 * contain both the RTP header and the payload.
 */
static pj_status_t transport_send_rtp(pjmedia_transport *tp, const void *pkt, pj_size_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter *)tp;
    pj_uint16_t esi, len, n, k;
    fec_ext_hdr fec_hdr;
    
    /* Encode the RTP packet with FEC Framework */
    pj_status_t status = fec_enc_pkt(adapter, pkt, size);
    
    
    if (status != PJ_SUCCESS)
    {
        PJ_LOG(4, (THIS_FILE, "Encode for send rtp failed with packet size=%u", size));
        return status;
    }
    
    /* Send the packet using the UDP transport if symbols block encoding complete */
    if (adapter->snd_ready == PJ_FALSE)
        return status;
    
    k = adapter->enc_params->nb_source_symbols;
    n = adapter->enc_params->nb_repair_symbols + adapter->enc_params->nb_source_symbols;
    
    /* Setup FEC header fields */
    fec_hdr.sn = pj_htonl(adapter->snd_sn);
    fec_hdr.k = pj_htons(adapter->enc_params->nb_source_symbols);
    fec_hdr.n = pj_htons(adapter->enc_params->nb_repair_symbols + adapter->enc_params->nb_source_symbols);
    fec_hdr.len = pj_htons(adapter->enc_params->encoding_symbol_length);
    
    for (esi = 0; esi < k; esi++)
    {
        /* Setup FEC header encoding symbol ID */
        fec_hdr.esi = pj_htons(esi);
        len = fec_enc_src((void *)enc_symbol_buf, enc_symbols_ptr[esi], enc_symbols_size[esi], &fec_hdr, &adapter->ext_hdr);
        
        if (len)
            status = pjmedia_transport_send_rtp(adapter->slave_tp, (void *)enc_symbol_buf, len);
        
        if (status != PJ_SUCCESS || !len)
            PJ_LOG(4, (THIS_FILE, "Send rtp failed with packet esi=%u, len=%u", esi, len));
    }
    
    for (; esi < n; esi++)
    {
        /* Setup FEC header encoding symbol ID */
        fec_hdr.esi = pj_htons(esi);
        len = fec_enc_rpr((void *)enc_symbol_buf, adapter->rtp_tx_ses, 0, enc_symbols_ptr[esi], enc_symbols_size[esi], &fec_hdr, &adapter->ext_hdr);
        
        if (len)
            status = pjmedia_transport_send_rtp(adapter->slave_tp, (void *)enc_symbol_buf, len);
        
        if (status != PJ_SUCCESS || !len)
            PJ_LOG(4, (THIS_FILE, "Send rtp failed with packet esi=%u, len=%u", esi, len));
    }
    
    /* Reset runtime encoding params */
    fec_enc_reset(adapter, n, adapter->enc_params->encoding_symbol_length);
    
    return status;
}


/*
 * send_rtcp() is called to send RTCP packet. The "pkt" and "size" argument
 * contain the RTCP packet.
 */
static pj_status_t transport_send_rtcp(pjmedia_transport *tp, const void *pkt, pj_size_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* You may do some processing to the RTCP packet here if you want. */
    
    /* Send the packet using the slave transport */
    return pjmedia_transport_send_rtcp(adapter->slave_tp, pkt, size);
}


/*
 * This is another variant of send_rtcp(), with the alternate destination
 * address in the argument.
 */
static pj_status_t transport_send_rtcp2(pjmedia_transport *tp, const pj_sockaddr_t *addr, unsigned addr_len, const void *pkt, pj_size_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    return pjmedia_transport_send_rtcp2(adapter->slave_tp, addr, addr_len, pkt, size);
}

/*
 * The media_create() is called when the transport is about to be used for
 * a new call.
 */
static pj_status_t transport_media_create(pjmedia_transport *tp, pj_pool_t *sdp_pool, unsigned options, const pjmedia_sdp_session *rem_sdp, unsigned media_index)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* if "rem_sdp" is not NULL, it means we are UAS. You may do some
     * inspections on the incoming SDP to verify that the SDP is acceptable
     * for us. If the SDP is not acceptable, we can reject the SDP by
     * returning non-PJ_SUCCESS.
     */
    if (rem_sdp)
    {
        /* Do your stuff.. */
    }
    
    /* Once we're done with our initialization, pass the call to the
     * slave transports to let it do it's own initialization too.
     */
    return pjmedia_transport_media_create(adapter->slave_tp, sdp_pool, options, rem_sdp, media_index);
}

/*
 * The encode_sdp() is called when we're about to send SDP to remote party,
 * either as SDP offer or as SDP answer.
 */
static pj_status_t transport_encode_sdp(pjmedia_transport *tp, pj_pool_t *sdp_pool, pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* If "rem_sdp" is not NULL, it means we're encoding SDP answer. You may
     * do some more checking on the SDP's once again to make sure that
     * everything is okay before we send SDP.
     */
    if (rem_sdp)
    {
        /* Do checking stuffs here.. */
    }
    
    /* You may do anything to the local_sdp, e.g. adding new attributes, or
     * even modifying the SDP if you want.
     */
    if (0)
    {
        /* Say we add a proprietary attribute here.. */
        pjmedia_sdp_attr *my_attr;
        
        my_attr = PJ_POOL_ALLOC_T(sdp_pool, pjmedia_sdp_attr);
        pj_strdup2(sdp_pool, &my_attr->name, "X-adapter");
        pj_strdup2(sdp_pool, &my_attr->value, "some value");
        
        pjmedia_sdp_attr_add(&local_sdp->media[media_index]->attr_count, local_sdp->media[media_index]->attr, my_attr);
    }
    
    /* And then pass the call to slave transport to let it encode its
     * information in the SDP. You may choose to call encode_sdp() to slave
     * first before adding your custom attributes if you want.
     */
    return pjmedia_transport_encode_sdp(adapter->slave_tp, sdp_pool, local_sdp, rem_sdp, media_index);
}

/*
 * The media_start() is called once both local and remote SDP have been
 * negotiated successfully, and the media is ready to start. Here we can start
 * committing our processing.
 */
static pj_status_t transport_media_start(pjmedia_transport *tp, pj_pool_t *pool, const pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    pj_uint32_t esi;
    
    adapter->dec_ses = NULL;
    
    /* Init Extension headers with default values */
    adapter->ext_hdr.profile_data = pj_htons(97);
    adapter->ext_hdr.length = pj_htons(sizeof(fec_ext_hdr) / sizeof(pj_uint32_t));
    
    adapter->rcv_sn = 0;
    
    /* Init pointers to symbol's buffers */
    for (esi = 0; esi < N_MAX; esi++)
    {
        enc_symbols_ptr[esi] = (void *)&enc_symbols_buf[esi * SYMBOL_SIZE_MAX];
        dec_symbols_ptr[esi] = (void *)&dec_symbols_buf[esi * SYMBOL_SIZE_MAX];
    }
    
    /* Fill in the code specific part of the of_..._parameters_t structure */
    /* Currently choose codec on n value */
    if (N_MAX <= 255)
    {
        adapter->codec_id = OF_CODEC_REED_SOLOMON_GF_2_M_STABLE;
        
        adapter->enc_rs_params.m = 8;
        adapter->enc_params = (of_parameters_t *)&adapter->enc_rs_params;
        
        adapter->dec_rs_params.m = 8;
        adapter->dec_params = (of_parameters_t *)&adapter->dec_rs_params;
    }
    else
    {
        adapter->codec_id = OF_CODEC_LDPC_STAIRCASE_STABLE;
        
        adapter->enc_ldps_params.prng_seed = rand();
        adapter->enc_ldps_params.N1 = 7;
        adapter->enc_params = (of_parameters_t *)&adapter->enc_ldps_params;
        
        adapter->dec_ldps_params.prng_seed = rand();
        adapter->dec_ldps_params.N1 = 7;
        adapter->dec_params = (of_parameters_t *)&adapter->dec_ldps_params;
    }
    
    /* And pass the call to the slave transport */
    return pjmedia_transport_media_start(adapter->slave_tp, pool, local_sdp, rem_sdp, media_index);
    
    PJ_LOG(4, (THIS_FILE, "Init fec codec failed"));
    
    return PJ_EINVAL;
}

/*
 * The media_stop() is called when media has been stopped.
 */
static pj_status_t transport_media_stop(pjmedia_transport *tp)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* Destroy FEC codecs */
    if (adapter->dec_ses)
        of_release_codec_instance(adapter->dec_ses);
    
    /* And pass the call to the slave transport */
    return pjmedia_transport_media_stop(adapter->slave_tp);
}

/*
 * simulate_lost() is called to simulate packet lost
 */
static pj_status_t transport_simulate_lost(pjmedia_transport *tp, pjmedia_dir dir, unsigned pct_lost)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    return pjmedia_transport_simulate_lost(adapter->slave_tp, dir, pct_lost);
}

/*
 * destroy() is called when the transport is no longer needed.
 */
static pj_status_t transport_destroy(pjmedia_transport *tp)
{
    struct tp_adapter *adapter = (struct tp_adapter*)tp;
    
    /* Close the slave transport */
    if (adapter->del_base)
    {
        pjmedia_transport_close(adapter->slave_tp);
    }
    
    /* Self destruct.. */
    pj_pool_release(adapter->pool);
    
    return PJ_SUCCESS;
}





