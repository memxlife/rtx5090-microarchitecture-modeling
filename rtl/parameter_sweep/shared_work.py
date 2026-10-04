"""Shared-read work rule checked against scalar warp-read profiler evidence.

This counts bank-service packages, not cycles or hardware ports.
"""
def shared_read_packages(word_addresses):
    if len(word_addresses)!=32 or any(not isinstance(a,int) or a<0 for a in word_addresses):
        raise ValueError('Exactly 32 nonnegative word addresses required')
    banks=[set() for _ in range(32)]
    for address in word_addresses:
        banks[address%32].add(address)
    return max(map(len,banks))

def shared_vector_packages(word_addresses,width_words,write=False):
    """Bounded measured full-warp rules for naturally aligned LDS/STS32/64/128.

    Reject unverified wide patterns instead of extrapolating scalar broadcasts.
    """
    if width_words not in (1,2,4):
        raise ValueError('Only measured scalar/64/128-bit widths supported')
    if len(word_addresses)!=32 or any(not isinstance(a,int) or a<0 or a%width_words for a in word_addresses):
        raise ValueError('32 naturally aligned, nonnegative word addresses required')
    if write and len(set(word_addresses))!=32:
        raise ValueError('Overlapping non-atomic vector stores are unsupported')
    if width_words==1:
        return shared_read_packages(word_addresses)
    base=word_addresses[0]
    if word_addresses==[base+lane*width_words for lane in range(32)]:
        return width_words
    if not write and len(set(word_addresses))==1:
        return 1 if width_words==2 else 2
    if write and word_addresses==[base+lane*32*width_words for lane in range(32)]:
        return 32
    raise ValueError('Wide shared access pattern needs additional hardware evidence')

def shared_broadcast128_packages(active_mask,byte_address=0):
    """Inferred LDS128 same-vector service rule, checked on ten lane masks.

    Each occupied 16-lane half contributes one package. This describes profile
    work for naturally aligned common-address reads, not latency or bank ports.
    Other addresses, vector widths, stores and LDSM operations are excluded.
    """
    if not isinstance(active_mask,int) or not 0<=active_mask<=0xffffffff:
        raise ValueError('A 32-bit active-lane mask is required')
    if not isinstance(byte_address,int) or byte_address<0 or byte_address%16:
        raise ValueError('A nonnegative 16-byte-aligned common address is required')
    return int(bool(active_mask&0xffff))+int(bool(active_mask>>16))

def ldsm_packages(row_byte_addresses,matrix_count):
    """Inferred all-lane LDSM service rule, checked in 24 configurations.

    Each eight-row provider group is counted separately. A row contains four
    32-bit words, even though the matrix elements are 16-bit. Transposition
    changes returned register contents but not this tested service-work rule.
    """
    if matrix_count not in (1,2,4):
        raise ValueError('Only measured x1/x2/x4 operations supported')
    if len(row_byte_addresses)!=32 or any(not isinstance(a,int) or a<0 or a%16 for a in row_byte_addresses):
        raise ValueError('32 nonnegative 16-byte-aligned row addresses required')
    packages=0
    for group in range(matrix_count):
        banks=[set() for _ in range(32)]
        for address in row_byte_addresses[group*8:(group+1)*8]:
            for word in range(address//4,address//4+4):banks[word%32].add(word)
        packages+=max(map(len,banks))
    return packages

def generic_scalar_read_work(address_space,byte_addresses):
    """Service routing for measured full-warp generic 32-bit reads.

    The caller supplies the resolved CUDA address space. Private pointer tags
    are unknown; this helper does not invent their encoding. Service work is
    distinct from timing. Global coverage is restricted to aligned contiguous
    reads; shared scalar bank work uses the existing measured bank rule.
    """
    if len(byte_addresses)!=32 or any(not isinstance(a,int) or a<0 or a%4 for a in byte_addresses):
        raise ValueError('32 nonnegative four-byte aligned lane addresses required')
    if address_space=='shared':
        return {'shared_packages':shared_read_packages([a//4 for a in byte_addresses]),'global_sectors':0}
    if address_space=='global':
        base=byte_addresses[0]
        if base%128 or byte_addresses!=[base+4*lane for lane in range(32)]:
            raise ValueError('Generic global service supports only measured aligned contiguous pattern')
        return {'shared_packages':0,'global_sectors':4}
    raise ValueError('Unresolved or unsupported address space')
