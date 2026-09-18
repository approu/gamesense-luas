local ffi = require "ffi"

ffi.cdef[[
    typedef struct {
        char pad0[8];
        int32_t client;
        int32_t audible_mask;
        uint32_t xuid_low;
        uint32_t xuid_high;
        void* voice_data;
        bool proximity;
        bool caster;
        char pad1[2];
        int32_t format;
        int32_t sequence_bytes;
        uint32_t section_number;
        uint32_t uncompressed_sample_offset;
    } voice_data_t;
]]

client.set_event_callback("voice", function(e)
    local p = ffi.cast("voice_data_t*", e.data)
    if not p then return end

    local target = p.client + 1
    if target ~= entity.get_local_player() then
        return  -- modifying only our packets
    end

    p.xuid_high = 0
    p.xuid_low = 0
    p.sequence_bytes = 0
    p.section_number = 0
    p.uncompressed_sample_offset = 0
end)
