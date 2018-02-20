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

#include <pjmedia/stream.h>
#include <pj/assert.h>
#include <pj/pool.h>
#include <pj/log.h>
#include "transport_adapter_fec.h"
#include <time.h>
#include <pjmedia/rtp.h>
#import "pjmedia/vid_stream.h"

//#pragma comment(lib, "openfec.lib")

 /*
 * Redundancy parameters DEFAULT_K, DEFAULT_N
 * CODE_RATE only for dynamic memory allocation (n = k / code_rate)
 * Change if required
 */

 /* FEC header struct */
typedef struct fec_ext_hdr
{
	pj_uint32_t				esi;					/* Encoding symbol ID */
	pj_uint32_t				sn;						/* Symbol sequence number (ecnoding block number) */
} fec_ext_hdr;

/* Symbol size, in bytes. Reserved place for ESI and sequence number */
#define SYMBOL_SIZE	(PJMEDIA_MAX_VID_PAYLOAD_SIZE - sizeof(fec_ext_hdr) - sizeof(pjmedia_rtp_ext_hdr) - sizeof(pjmedia_rtp_hdr))
#define	DEFAULT_K	10														/* Default k value */
#define CODE_RATE	0.667													/* k/n = 2/3 means we add 50% of repair symbols. Use DEFAULT_N instead */
#define DEFAULT_N	12														/* n value = k/code_rate means we add 20% of repair symbols */
#define RTP_VERSION 2

 /* For logging purpose. */
#define THIS_FILE   "adap_openfec"

/* Encoding buffers. We'll update it progressively */
static void*		enc_symbols_ptr[DEFAULT_N];					/* Table containing pointers to the encoding (i.e. source + repair) symbols buffers */
static char			enc_symbols_buf[SYMBOL_SIZE * DEFAULT_N];	/* Buffer containing encoding (i.e. source + repair) symbols */
static pj_uint32_t	enc_symbols_size[DEFAULT_N];				/* Table containing network(real) sizes of the encoding symbols(packets) (i.e. source + repair) */
/* Decoding buffers. We'll update it progressively */
static void*		dec_symbols_ptr[DEFAULT_N];					/* Table containing pointers to the decoding (i.e. source + repair) symbols buffers */
static char			dec_symbols_buf[SYMBOL_SIZE * DEFAULT_N];	/* Buffer containing decoding (i.e. source + repair) symbols */
static pj_uint32_t	dec_symbols_size[DEFAULT_N];				/* Table containing network(real) sizes of the decoding symbols(packets) (i.e. source + repair) */

static pj_uint32_t	random_index[DEFAULT_N];

/* Transport functions prototypes */
static pj_status_t	transport_get_info		(pjmedia_transport *tp, pjmedia_transport_info *info);
static pj_status_t	transport_attach2		(pjmedia_transport *tp, pjmedia_transport_attach_param *att_prm);
static void			transport_detach		(pjmedia_transport *tp, void *strm);
static pj_status_t	transport_send_rtp		(pjmedia_transport *tp, const void *pkt, pj_size_t size);
static pj_status_t	transport_send_rtcp		(pjmedia_transport *tp, const void *pkt, pj_size_t size);
static pj_status_t	transport_send_rtcp2	(pjmedia_transport *tp, const pj_sockaddr_t *addr, unsigned addr_len, const void *pkt, pj_size_t size);
static pj_status_t	transport_media_create	(pjmedia_transport *tp, pj_pool_t *sdp_pool, unsigned options, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t	transport_encode_sdp	(pjmedia_transport *tp, pj_pool_t *sdp_pool, pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t	transport_media_start	(pjmedia_transport *tp, pj_pool_t *pool, const pjmedia_sdp_session *local_sdp, const pjmedia_sdp_session *rem_sdp, unsigned media_index);
static pj_status_t	transport_media_stop	(pjmedia_transport *tp);
static pj_status_t	transport_simulate_lost	(pjmedia_transport *tp, pjmedia_dir dir, unsigned pct_lost);
static pj_status_t	transport_destroy		(pjmedia_transport *tp);

/* FEC functions prototypes */
static void*		fec_dec_src_cb			(void *context /* TP adapter */, pj_uint32_t size, pj_uint32_t esi);
static void*		fec_dec_rpr_cb			(void *context /* TP adapter */, pj_uint32_t size, pj_uint32_t esi);
static pj_status_t	fec_init_codec			(void *user_data /* TP adapter */, of_codec_type_t codec_type);
static pj_status_t	fec_destroy				(void *user_data /* TP adapter */);
static pj_status_t	fec_encode				(void *user_data /* TP adapter */, const void *pkt, pj_size_t size);
static void			fec_randomize_array		(void **array, const pj_uint32_t len);
static pj_size_t	fec_symbol_size			(const void *pkt, const pj_uint32_t symbol_size);
//static void*		fec_enc_hdr				(const void *pkt, const fec_ext_hdr *hdr);
//static void*		fec_dec_hdr				(const void *pkt, fec_ext_hdr *hdr);
static pj_uint32_t	fec_enc_src				(void *dst, const void *pkt, pj_uint32_t size, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr);
static pj_uint32_t  fec_enc_rpr				(void *dst, pjmedia_rtp_session *ses, int ts_len, const void *payload, pj_uint32_t payload_len, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr);
static void*		fec_dec_fec_hdr			(const void *pkt, fec_ext_hdr *fec_hdr);
static pj_uint32_t	fec_dec_fec_pkt			(void *dst, void *pkt, pj_uint32_t size, pj_bool_t rtp);

/* The transport operations */
static struct pjmedia_transport_op tp_adapter_op = 
{
    &transport_get_info,
    NULL,
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
    &transport_attach2,
};

/* Statistics/numbering counters */
typedef struct fec_tp_stat
{
	pj_uint32_t				enc_src_ok;					/* Total number of source symbols through session */
	pj_uint32_t				enc_rpr_ok;					/* Total number of repair symbols through session */
	pj_uint32_t				enc_rpr_err;				/* Total number of repair symbol build error through session */
	pj_uint32_t				snd_ok;						/* Total number of symbols sent through session */
	pj_uint32_t				snd_err;					/* Total number of symbols send error through session */
	pj_uint32_t				rcv_ok;
	pj_uint32_t				rcv_err;
	pj_uint32_t				dec_src_ok;
	pj_uint32_t				dec_rpr_ok;
} fec_tp_stat;

/* The transport adapter instance */
struct tp_adapter
{
    pjmedia_transport	base;
    pj_bool_t			del_base;
    pj_pool_t			*pool;

    /* Stream information. */
    void				*stream_user_data;
    void                *stream_ref;
    void				(*stream_rtp_cb)(void *user_data, void *pkt, pj_ssize_t);
    void				(*stream_rtcp_cb)(void *user_data, void *pkt, pj_ssize_t);


    pjmedia_transport		*slave_tp;					/* Base transport pointer */

	/* FEC specific encoding/decoding members */
	of_codec_id_t			codec_id;					/* Identifier of the codec to use */
	of_session_t			*dec_ses;					/* openfec decoder instance identifier */
	of_session_t			*enc_ses;					/* openfec encoder instance identifier */
	of_parameters_t			*params;					/* Pointer to specific algorithm params */

	of_rs_2_m_parameters_t	rs_params;					/* Structure used to store Reed-Solomon codes over GF(2^m) params */
	of_ldpc_parameters_t	ldps_params;				/* Structure used to store LDPC-Staircase large block FEC codes params */

	pjmedia_stream_rtp_sess_info rtp_ses_info;
	pjmedia_rtp_session		*rtp_ses;					/* Pointer to current RTP session */
	
	pjmedia_rtp_hdr			rtp_hdr;					/* RTP header with common default values for encoding repair symbols */
	pjmedia_rtp_ext_hdr		ext_hdr;					/* RTP Extension header with common default values for encoding purpose */
	fec_ext_hdr				fec_hdr;					/* RTP Extension header data with common FEC encoding session values */

	/* FEC specific runtime values */
	pj_uint32_t				snd_k;						/* Current number of ready to send source symbols in the block */
	pj_uint32_t				snd_sn;						/* Current number of encoding symbol's sequence */
	pj_uint32_t				rcv_k;						/* Current number of recieved source/repair symbols in the block */
	pj_uint32_t				rcv_sn;						/* Current number of decoding symbol's sequence */
	fec_tp_stat				stat;						/* Statistics/numbering counters */
};

/**
* Dumps len32 32-bit words of a buffer (typically a symbol).
*/
static void dump_pkt(const void *buf, const pj_uint32_t size, pj_uint32_t esi, const char *type)
{
	char	*ptr;
	pj_uint32_t	n = size;
	char str[SYMBOL_SIZE * 3] = { '\0' }, *p = str;

	p += sprintf(p, "%s_%03u size=%u: ", type, esi, size);
	p += sprintf(p, "0x");
	for (ptr = (char *)buf; n > 0; n--, ptr++)
	{
		p += sprintf(p, "%hhX", *ptr);
	}
	p += sprintf(p, "\n");

	PJ_LOG(4, (THIS_FILE, str));
}

/* Currently get packet real size, because openfec encode repair packet using size padding */
static pj_size_t fec_symbol_size(const void *pkt, const pj_uint32_t symbol_size)
{
	/* Pointer to end of packet buffer */
	char *ptr = (char *)pkt + symbol_size - 1;
	pj_uint32_t size = symbol_size;

	while (!*ptr-- && size)
		--size;

	return size;
}

static pj_status_t fec_init_codec(void *user_data, of_codec_type_t codec_type)
{
	struct tp_adapter *adapter = (struct tp_adapter *)user_data;
	pj_status_t status = PJ_SUCCESS;
	pj_uint32_t esi, n, len;
	of_session_t *ses;

	if (!adapter)
		return PJ_EINVAL;

	/* Init counters */
	/*adapter->snd_k = 0;

	adapter->stat.enc_src_ok = 0;
	adapter->stat.enc_rpr_ok = 0;
	adapter->stat.enc_rpr_err = 0;
	adapter->stat.snd_ok = 0;
	adapter->stat.snd_err = 0;

	adapter->rcv_k = 0;

	adapter->stat.rcv_ok = 0;
	adapter->stat.dec_src_ok = 0;
	adapter->stat.dec_rpr_ok = 0;*/

	/* Init pointers to symbol's buffers */
	//for (esi = 0; esi < n; esi++)
	//{
	//	enc_symbols_ptr[esi] = (void *)&enc_symbols_buf[esi * symbol_size];
	//	/* Init random index array for shuffle send */
	//	random_index[esi] = esi;

	//	dec_symbols_ptr[esi] = (void *)&dec_symbols_buf[esi * symbol_size];
	//	memset(dec_symbols_ptr[esi], 0, symbol_size);
	//}

	/* Decoder reinit */
	if (codec_type == OF_DECODER)
	{
		if (adapter->dec_ses)
			of_release_codec_instance(adapter->dec_ses);

		n = adapter->params->nb_repair_symbols + adapter->params->nb_source_symbols;
		len = adapter->params->encoding_symbol_length;

		for (esi = 0; esi < n; esi++)
		{
			//memset(dec_symbols_ptr[esi], 0, symbol_size);
			memset(dec_symbols_ptr[esi], 0, len);
			dec_symbols_size[esi] = 0;
		}

		adapter->rcv_k = 0;
	}

	/* Fill in the code specific part of the of_..._parameters_t structure */
	/* Currently choose codec on n value */
	//if (n <= 255)
	//{
	//	adapter->codec_id = OF_CODEC_REED_SOLOMON_GF_2_M_STABLE;
	//	adapter->rs_params.m = 8;
	//	adapter->params = (of_parameters_t *)&adapter->rs_params;
	//}
	//else
	//{
	//	adapter->codec_id = OF_CODEC_LDPC_STAIRCASE_STABLE;
	//	adapter->ldps_params.prng_seed = rand();
	//	adapter->ldps_params.N1 = 7;
	//	adapter->params = (of_parameters_t *)&adapter->ldps_params;
	//}
	//
	///* Fill in the generic part of the of_parameters_t structure */
	//adapter->params->nb_source_symbols = k;
	//adapter->params->nb_repair_symbols = n - k;
	//adapter->params->encoding_symbol_length = symbol_size;

	/* Open and initialize the openfec session */
	//if (of_create_codec_instance(&adapter->ses, adapter->codec_id, OF_ENCODER_AND_DECODER, 2 /* Verbosity */) != OF_STATUS_OK)
	if (of_create_codec_instance(&ses, adapter->codec_id, codec_type, 2 /* Verbosity */) != OF_STATUS_OK)
	{
		status = PJ_EINVAL;
		PJ_LOG(4, (THIS_FILE, "Create codec instance failed"));
	}
	/* Set session parameters */
	if (status == PJ_SUCCESS && of_set_fec_parameters(ses, adapter->params) != OF_STATUS_OK)
	{
		status = PJ_EINVAL;
		PJ_LOG(4, (THIS_FILE, "Set parameters failed for codec_id=%d", adapter->codec_id));
	}
	/* Setup callbacks for decoding */
	if (codec_type == OF_DECODER && status == PJ_SUCCESS)
	{
		if (of_set_callback_functions(ses, fec_dec_src_cb, fec_dec_rpr_cb, adapter) != OF_STATUS_OK)
		{
			status = PJ_EINVAL;
			PJ_LOG(4, (THIS_FILE, "Set callback functions failed for decoder with codec_id=%d", adapter->codec_id));
		}
	}

	/* Cleanup session on fail */
	if (status != PJ_SUCCESS && ses)
		of_release_codec_instance(ses);
	else if (codec_type == OF_DECODER)
	{
		adapter->dec_ses = ses;
	}
	else if (codec_type == OF_ENCODER)
	{
		adapter->enc_ses = ses;
	}

	return status;
}

static pj_status_t fec_destroy(void *user_data)
{
	struct tp_adapter *adapter = (struct tp_adapter *)user_data;

	/* Cleanup session */
	if (adapter)
	{
		/* Print statistics */
		// TODO

		if (of_release_codec_instance(adapter->enc_ses) == OF_STATUS_OK
			&& of_release_codec_instance(adapter->dec_ses) == OF_STATUS_OK)
			return PJ_SUCCESS;
	}

	return PJ_EINVAL;
}

static pj_status_t fec_encode(void *user_data, const void *pkt, pj_size_t size)
{
	struct tp_adapter	*adapter = (struct tp_adapter *)user_data;
	pj_uint32_t			esi;
	pj_uint32_t			n, k, len;

	if (!adapter || !pkt)
		return PJ_EINVAL;

	k = adapter->params->nb_source_symbols;
	n = adapter->params->nb_repair_symbols + adapter->params->nb_source_symbols;
	len = adapter->params->encoding_symbol_length;

	/* Put to table only if current count of symbols less than k */
	if (adapter->snd_k < k)
	{
		/* Clear symbol buffer */			
		memset(enc_symbols_ptr[adapter->snd_k], 0, len);
		memcpy(enc_symbols_ptr[adapter->snd_k], pkt, size);
		/* Encode source symbol */
		//adapter->fec_hdr.esi = adapter->snd_k;
		//size = fec_enc_src(enc_symbols_ptr[adapter->snd_k], pkt, size, &adapter->fec_hdr, &adapter->ext_hdr);
		
		//if (!size)
		//	return PJ_EINVAL;

		/* Remember real size for source symbols */
		enc_symbols_size[adapter->snd_k] = size;

		adapter->snd_k++;

		/* Statistics */
		adapter->stat.enc_src_ok++;
	}

	if (adapter->snd_k < k)
		return PJ_SUCCESS;

#if 1
	/* Sequence counter for symbols block */
	adapter->snd_sn++;

	/* Build the n-k repair symbols if count of symbols is enough */
	for (esi = k; esi < n; esi++)
	{
		if (of_build_repair_symbol(adapter->enc_ses, enc_symbols_ptr, esi) != OF_STATUS_OK)
		{
			adapter->stat.enc_rpr_err++;
			PJ_LOG(4, (THIS_FILE, "Build repair symbol failed for esi=%u", esi));
			return PJ_EINVAL;
		}

		/* Set repair symbol length to max value */
		enc_symbols_size[esi] = len;

		/* Statistics */
		adapter->stat.enc_rpr_ok++;
	}
#endif
	return PJ_SUCCESS;
}

/* Restore callback for source packets */
static void* fec_dec_src_cb(void *context, pj_uint32_t size, pj_uint32_t esi)
{
	struct tp_adapter *adapter = (struct tp_adapter*)context;

	/* Statistics */
	if (adapter)
		adapter->stat.dec_src_ok++;
		
	// dec_symbols_size[esi] = size;

	/* Must return buffer pointer for decoder to save restored source packet */
	return dec_symbols_ptr[esi];
}

/* Restore callback for repair packets. Statistics only */
static void* fec_dec_rpr_cb(void *context, pj_uint32_t size, pj_uint32_t esi)
{
	struct tp_adapter *adapter = (struct tp_adapter*)context;

	/* Statistics */
	if (adapter)
		adapter->stat.dec_rpr_ok++;

	return dec_symbols_ptr[esi];
}

/* Put FEC header in symbol buffer and return pointer to payload area start */
//static void* fec_enc_hdr(const void *pkt, const fec_ext_hdr *hdr)
//{
//	pj_uint32_t *ptr = pkt;
//
//	*ptr++ = pj_htonl(hdr->esi);
//	*ptr++ = pj_htonl(hdr->sn);
//
//	return (void *)ptr;
//}

/* Construct in destination buffer packet with Extension header and data based on original RTP source symbol */
static pj_uint32_t fec_enc_src(void *dst, const void *pkt, pj_uint32_t size, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr)
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
	ptr = (pj_uint8_t *)ptr + (pj_uint8_t)num;
	
	/* Remember payload offset in original packet and decrease copy left size */
	pkt = (pj_uint8_t *)pkt + (pj_uint8_t)num;
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
//static pj_uint32_t fec_enc_rpr(void *dst, const void *payload, pj_uint32_t payload_len, const void *hdr, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr)
static pj_uint32_t fec_enc_rpr(void *dst, pjmedia_rtp_session *ses, int ts_len, const void *payload, pj_uint32_t payload_len, const fec_ext_hdr *fec_hdr, const pjmedia_rtp_ext_hdr *ext_hdr)
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

static void* fec_dec_fec_hdr(const void *pkt, fec_ext_hdr *fec_hdr)
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

	fec_hdr->esi = pj_ntohl(*(pj_uint32_t *)ptr);
	ptr += sizeof(pj_uint32_t);
	fec_hdr->sn = pj_ntohl(*(pj_uint32_t *)ptr);
	ptr += sizeof(pj_uint32_t);

	return ptr;
}

static pj_uint32_t fec_dec_fec_pkt(void *dst, void *pkt, pj_uint32_t size, pj_bool_t rtp)
{
	unsigned num;
	pj_uint8_t *ptr = (pj_uint8_t *)dst;
	pjmedia_rtp_hdr *rtp_hdr = (pjmedia_rtp_hdr *)pkt;

	pj_assert(rtp_hdr->v == RTP_VERSION);

	/* Size of RTP header plus CSRCs until Extension header */
	num = sizeof(pjmedia_rtp_hdr) + rtp_hdr->cc * sizeof(pj_uint32_t);

	/* Copy RTP header */
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
	pkt = (pj_uint8_t *)pkt + (pj_uint8_t)num;
	size -= num;

	memcpy(ptr, pkt, size);
	ptr += size;

	return (ptr - (pj_uint8_t *)dst);
}

/* Get FEC header in symbol buffer and return pointer to payload area start */
//static void* fec_dec_fec_hdr(const void *pkt, fec_ext_hdr *hdr)
//{
//	pj_uint32_t *ptr = pkt;
//
//	hdr->esi = pj_ntohl(*ptr++);
//	hdr->sn = pj_ntohl(*ptr++);
//
//	return (void *)ptr;
//}

/* Randomize an array */
void fec_randomize_array(void **array, const pj_uint32_t len)
{
	void		*backup = 0;
	pj_uint32_t randInd = 0;		
	pj_uint32_t	i;

	/* random seed for the srand() function bu current time */
	srand((unsigned)time(NULL));

	for (i = 0; i < len; i++)
	{
		backup = array[i];
		randInd = rand() % len;
		array[i] = array[randInd];
		array[randInd] = backup;
	}
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


/* This is our RTP callback, that is called by the slave transport when it
 * receives RTP packet.
 */
static void transport_rtp_cb(void *user_data, void *pkt, pj_ssize_t size)
{
    struct tp_adapter *adapter = (struct tp_adapter*)user_data;
	pj_uint32_t esi, k = adapter->params->nb_source_symbols;
	pj_uint32_t n = adapter->params->nb_repair_symbols + k;
	pj_uint32_t len = adapter->params->encoding_symbol_length;
	fec_ext_hdr fec_hdr;

    pj_assert(adapter->stream_rtp_cb != NULL);
	pj_assert(size > 2 * sizeof(pj_uint32_t));

	adapter->stat.rcv_ok++;
	adapter->rcv_k++;
#if 1

	/* Decode FEC header before FEC decoding */
	fec_dec_fec_hdr(pkt, &fec_hdr);

	/* Sanity check */
	if(fec_hdr.esi > n)
	{
		PJ_LOG(4, (THIS_FILE, "Invalid esi=%u received in a packet's FPI", fec_hdr.esi));
		return;
	}

	/* Check packet FEC sequence number */
	if (fec_hdr.sn < adapter->rcv_sn)
	{
		PJ_LOG(4, (THIS_FILE, "Too late seq_num=%u received in a packet while decoder seq_num=%u, skip", fec_hdr.sn, adapter->rcv_sn));
		return;
	}
	/* New sequence packet */
	else if (fec_hdr.sn > adapter->rcv_sn)
	{
		if (!of_is_decoding_complete(adapter->dec_ses))
			PJ_LOG(4, (THIS_FILE, "Decoding incomplete for seq_num=%u, reset for new seq_num=%u", adapter->rcv_sn, fec_hdr.sn));

		adapter->rcv_sn = fec_hdr.sn;
		/* Create new decoder session for new FEC sequence */
		fec_init_codec(adapter, OF_DECODER);
	}
	else if (of_is_decoding_complete(adapter->dec_ses))
	{
		//PJ_LOG(4, (THIS_FILE, "Decoding complete for seq_num=%u, skip", fec_hdr.sn));
		return;
	}

	/* Decode packet */
	size = fec_dec_fec_pkt(dec_symbols_ptr[fec_hdr.esi], pkt, size, fec_hdr.esi < k ? PJ_TRUE : PJ_FALSE);

	dec_symbols_size[fec_hdr.esi] = size;

	/*
	* Submit each fresh symbol to the library, upon reception
	* using the standard of_decode_with_new_symbol() function.
	*/
	if (of_decode_with_new_symbol(adapter->dec_ses, dec_symbols_ptr[fec_hdr.esi], fec_hdr.esi) == OF_STATUS_ERROR)
	{
		adapter->stat.rcv_err++;
		PJ_LOG(4, (THIS_FILE, "Decode with new symbol failed esi=%u, len=%u", fec_hdr.esi, len));
	}

	/* Exit if decoding not complete */
	if (!of_is_decoding_complete(adapter->dec_ses))
		return;

	//PJ_LOG(4, (THIS_FILE, "Decoded seq_num=%u", fec_hdr.sn));

	/* Call stream's callback for all source symbols in buffer */
	for (esi = 0; esi < k; esi++)
	{
		/* Get repaired packet real size */
		if (!dec_symbols_size[esi])
			dec_symbols_size[esi] = fec_symbol_size(dec_symbols_ptr[esi], len);

		adapter->stream_rtp_cb(adapter->stream_user_data, dec_symbols_ptr[esi], dec_symbols_size[esi]);
	}

#else
	adapter->stream_rtp_cb(adapter->stream_user_data, pkt, size);
#endif
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
    pjmedia_vid_stream_get_rtp_session_info(adapter->stream_ref, &adapter->rtp_ses_info);

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
	pj_uint32_t k = adapter->params->nb_source_symbols;
	pj_uint32_t i, esi, n = k + adapter->params->nb_repair_symbols;
	pj_uint32_t len = 0;
	fec_ext_hdr fec_hdr;
	pj_uint8_t buf[SYMBOL_SIZE + sizeof(fec_ext_hdr) + sizeof(pjmedia_rtp_ext_hdr) + sizeof(pjmedia_rtp_hdr)];

    /* Encode the RTP packet with FEC Framework */
	//esi = adapter->snd_k;
	//dump_pkt(pkt, size, esi, "enc");
	pj_status_t status = fec_encode(adapter, pkt, size);
	//dump_pkt(enc_symbols_ptr[esi], enc_symbols_size[esi], esi, "cpy");

	if (status != PJ_SUCCESS)
	{
		PJ_LOG(4, (THIS_FILE, "Encode for send rtp failed with packet size=%u", size));
		return status;
	}

	/* Send the packet using the UDP transport if symbols block encoding complete */
	if (adapter->snd_k == k)
	{
		/* Randomize before send */
		//fec_randomize_array(random_index, n);

		fec_hdr.sn = pj_htonl(adapter->snd_sn);

		for (esi = 0; esi < n; esi++)
		//for (i = 0; i < n; i++) 
		{	
			//esi = random_index[i];
#if 1
			/* Add a pkt FEC header, in network byte order in order
			* to be portable regardless of the local and remote byte endian representation (the receiver will do the
			* opposite with ntohl()...) */
			//*(pj_uint32_t *)buf = pj_htonl(esi);
			//*(pj_uint32_t *)(buf + sizeof(pj_uint32_t)) = pj_htonl(adapter->snd_sn);
			//memcpy((void *)(buf + sizeof(fec_hdr)), enc_symbols_ptr[esi], enc_symbols_size[esi]);

			fec_hdr.esi = pj_htonl(esi);
			// memcpy(fec_enc_hdr((void *)buf, &fec_hdr), enc_symbols_ptr[esi], enc_symbols_size[esi]);
			if (esi < k)
				len = fec_enc_src((void *)buf, enc_symbols_ptr[esi], enc_symbols_size[esi], &fec_hdr, &adapter->ext_hdr);
			else	
				len = fec_enc_rpr((void *)buf, adapter->rtp_ses_info.tx_rtp, 0, enc_symbols_ptr[esi], enc_symbols_size[esi], &fec_hdr, &adapter->ext_hdr);
			
			// DEBUG
			pjmedia_rtp_hdr *_hdr;
			void *payload;
			unsigned payload_len;
			status = pjmedia_rtp_decode_rtp(NULL, (void *)buf, len, &_hdr, &payload, &payload_len);
			pj_assert(status == PJ_SUCCESS);
			//dump_pkt((void *)buf, len, esi, "snd");

			if (len)
				status = pjmedia_transport_send_rtp(adapter->slave_tp, (void *)buf, len);

			/* Send packets with real size plus FEC header size */
			//status = pjmedia_transport_send_rtp(adapter->slave_tp, (void *)buf, enc_symbols_size[esi] + sizeof(fec_ext_hdr));
			
#else
			//dump_pkt(enc_symbols_ptr[esi], enc_symbols_size[esi], esi, "snd");
			status = pjmedia_transport_send_rtp(adapter->slave_tp, enc_symbols_ptr[esi], enc_symbols_size[esi]);
#endif
			if (status != PJ_SUCCESS || !len)
			{
				adapter->stat.snd_err++;
				PJ_LOG(4, (THIS_FILE, "Send rtp failed with packet esi=%u, len=%u", esi, len));
				break;
			}

			adapter->stat.snd_ok++;
		}
		
		/* Reset */
		adapter->snd_k = 0;
	}

	return status;

	//return pjmedia_transport_send_rtp(adapter->slave_tp, pkt, size);
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
	adapter->enc_ses = NULL;

	/* Init Extension headers with default values */
	adapter->ext_hdr.profile_data = pj_htons(97);
	adapter->ext_hdr.length = pj_htons(sizeof(fec_ext_hdr) / sizeof(pj_uint32_t));

	/* Init stat counters */
	adapter->stat.enc_src_ok = 0;
	adapter->stat.enc_rpr_ok = 0;
	adapter->stat.enc_rpr_err = 0;
	adapter->stat.snd_ok = 0;
	adapter->stat.snd_err = 0;

	adapter->stat.rcv_ok = 0;
	adapter->stat.dec_src_ok = 0;
	adapter->stat.dec_rpr_ok = 0;

	adapter->rcv_sn = 0;

	/* Init pointers to symbol's buffers */
	for (esi = 0; esi < DEFAULT_N; esi++)
	{
		enc_symbols_ptr[esi] = (void *)&enc_symbols_buf[esi * SYMBOL_SIZE];
		dec_symbols_ptr[esi] = (void *)&dec_symbols_buf[esi * SYMBOL_SIZE];

		/* Also init random index array for shuffle send */
		random_index[esi] = esi;
	}

	/* Fill in the code specific part of the of_..._parameters_t structure */
	/* Currently choose codec on n value */
	if (DEFAULT_N <= 255)
	{
		adapter->codec_id = OF_CODEC_REED_SOLOMON_GF_2_M_STABLE;
		adapter->rs_params.m = 8;
		adapter->params = (of_parameters_t *)&adapter->rs_params;
	}
	else
	{
		adapter->codec_id = OF_CODEC_LDPC_STAIRCASE_STABLE;
		adapter->ldps_params.prng_seed = rand();
		adapter->ldps_params.N1 = 7;
		adapter->params = (of_parameters_t *)&adapter->ldps_params;
	}

	/* Fill in the generic part of the of_parameters_t structure */
	adapter->params->nb_source_symbols = DEFAULT_K;
	adapter->params->nb_repair_symbols = DEFAULT_N - DEFAULT_K;
	adapter->params->encoding_symbol_length = SYMBOL_SIZE;

    /* Init FEC codec */
	if (fec_init_codec((void *)adapter, OF_ENCODER) == PJ_SUCCESS &&
		fec_init_codec((void *)adapter, OF_DECODER) == PJ_SUCCESS)
	{
		/* And pass the call to the slave transport */
		return pjmedia_transport_media_start(adapter->slave_tp, pool, local_sdp, rem_sdp, media_index);
	}

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
	fec_destroy((void *)adapter);

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





