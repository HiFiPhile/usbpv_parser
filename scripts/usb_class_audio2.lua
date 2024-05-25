-- usb_class_audio.lua

-- a typical class has these functions
-- cls.parse_setup(setup, context),  update setup.html, setup.name field in setup, and return it
-- cls.parse_setup_data(setup, data, context)    return a html to describe the data
-- cls.on_transaction(self, param, data, needDetail, forceBegin)  return macro_defs.RES_xxx
-- cls.descriptor_parser(data, offset, context)   return a parsed descriptor
-- cls.get_name(descriptor, context)              return a field name table
-- Audio class definition  https://www.usb.org/sites/default/files/audio10.pdf

local html = require("html")
local macro_defs = require("macro_defs")
local setup_parser = require("usb_setup_parser")
local unpack = string.unpack
require("usb_register_class")

local cls = {}

function toBits(num,bits)
    -- returns a table of bits, most significant first.
    bits = bits or math.max(1, select(2, math.frexp(num)))
    local t = {} -- will contain the bits
    for b = bits, 1, -1 do
        t[b] = math.fmod(num, 2)
        num = math.floor((num - t[b]) / 2)
    end
    return table.concat(t)
end

local audio_as_decoder = {}
local function install_decoder(decoder)
    for k,v in pairs(decoder.audio_decoder) do
        assert(not audio_as_decoder[k], "Audio Decoder already exist for " .. k)
        audio_as_decoder[k] = v
    end
end
install_decoder( require("decoder_audio_payload_typeI") )

local req2str = {
    [0x00] = "Undefined",
    [0x01] = "Cur",
    [0x02] = "Range",
    [0x03] = "Mem",
}

local field_wIndex_intf_audio = html.create_field([[
    struct{
        // wIndex
        uint16_t Interface:8;
        uint16_t EntityID:8;
    }
]])

local field_wIndex_endp_audio = html.create_field([[
    struct{
        // wIndex
        uint16_t Endpoint:8;
        uint16_t EntityID:8;
    }
]])

local field_wValue_audio = html.create_field([[
    struct{
        // wValue
        uint16_t ChannelNumber:8;
        uint16_t ControlSelector:8;
    }
]])

local audio_render_selector

function cls.parse_setup(setup, context)
    if setup.recip == "Interface" and setup.type == "Standard" and setup.bRequest == macro_defs.SET_INTERFACE then
        local itf = setup.wIndex & 0xff
        local itf_data = context:get_interface_data(itf)
        itf_data.alt_setting = setup.wValue
        return
    end

    if (setup.recip ~= "Interface" and setup.recip ~= "Endpoint") or setup.type ~= "Class" then
        return
    end
    local dir = setup.bmRequest >> 7
    local rcpt = setup.bmRequest & 3
    if dir == 1 then
        dir_str = "Get "
    else
        dir_str = "Set "
    end
    local bRequest_desc = req2str[setup.bRequest] or "Audio Unknown"
    setup.name = dir_str .. bRequest_desc
    setup.title = "Audio Request"
    setup.render.bRequest = bRequest_desc
    setup.render.wValue = field_wValue_audio
    if rcpt == 1 then
        setup.render.wIndex = field_wIndex_intf_audio
    else
        setup.render.wIndex = field_wIndex_endp_audio
    end
    setup.render.title = "Audio Request " .. dir_str .. bRequest_desc
    audio_render_selector(setup, context)
end

function cls.parse_setup_data(setup, data, context)
    if setup.audio_data_render then
        local res = setup.audio_data_render(data)
        return res
    end
end

local struct_audio_sync_endpoint_desc = html.create_struct([[
    uint8_t  bLength;          // {format = "dec"}
    uint8_t  bDescriptorType;  // _G.get_descriptor_name
    // bEndpointAddress
    uint8_t  EndpointAddress:4;
    uint8_t  Reserved:3;
    uint8_t  Direction:1;     // {[0] ="OUT", [1]="IN"}
    // bmAttributes
    uint8_t  Type:2;          // {[0]="Control", [1]="Isochronous", [2]="Bulk", [3]="Interrupt"}
    uint8_t  SyncType:2;      // {[0]="No Synchonisation", [1]="Asynchronous", [2]="Adaptive", [3]="Synchronous"}
    uint8_t  UsageType:2;     // {[0]="Data Endpoint", [1]="Feedback Endpoint", [2]="Implicit Feedback Endpoint"}
    uint8_t  Reserved:2;
    uint16_t wMaxPacketSize;  // {format = "dec"}
    uint8_t  bInterval;
]])

local function make_ac_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "AC Interface " .. name .. " Descriptor")
    end
end
local function make_as_interface(name, info)
    local builder = html.create_struct(info)
    return function(data, offset, context)
        return builder:build(data:sub(offset), "AS Interface " .. name .. " Descriptor")
    end
end

_G.audio_interface_desc_type = {
    [0x00] = "Undefined",
    [0x01] = "Header",
    [0x02] = "Input Terminal",
    [0x03] = "Output Terminal",
    [0x04] = "Mixer Unit",
    [0x05] = "Selector Unit",
    [0x06] = "Feature Unit",
    [0x07] = "Effect Unit",
    [0x08] = "Processing Unit",
    [0x09] = "Extension Unit",
    [0x0a] = "Clock Source",
    [0x0b] = "Clock Selector",
    [0x0c] = "Clock Multiplier",
    [0x0d] = "Sample Rate Converter",
}
-- audio terminal types
_G.audio_terminal_types = {
    [0x0100] = "USB Undefined",
    [0x0101] = "USB Stream",
    [0x01ff] = "USB Vendor specific",

    [0x0200] = "Input Undefined",

    [0x0201] = "Microphone",
    [0x0202] = "Desktop Microphone",
    [0x0203] = "Personal Microphone",
    [0x0204] = "Omni-directional Microphone",
    [0x0205] = "Microphone Array",
    [0x0206] = "Processing Microphone Array",

    [0x0300] = "Output Undefined",
    [0x0301] = "Speaker",
    [0x0302] = "Headphones",
    [0x0303] = "Head Mounted Display Audio",
    [0x0304] = "Desktop speaker",
    [0x0305] = "Room speaker",
    [0x0306] = "Communication speaker",
    [0x0307] = "Low frequency effects speaker",

    [0x0400] = "Bi-directional Undefined",
    [0x0401] = "Handset",
    [0x0402] = "Headset",
    [0x0403] = "Speakerphone",
    [0x0404] = "Echo-suppressing speakerphone",
    [0x0405] = "Echo-canceling speakerphone",

    [0x0500] = "Telephony Undefined",
    [0x0501] = "Phone line",
    [0x0502] = "Telephone",
    [0x0503] = "Down Line Phone",

    [0x0600] = "External Undefined",
    [0x0601] = "Analog connector",
    [0x0602] = "Digital audio interface",
    [0x0604] = "Legacy audio connector",
    [0x0605] = "S/PDIF interface",
    [0x0606] = "1394 DA stream",
    [0x0607] = "1394 DV stream soundtrack",

    [0x0700] = "Embedded Undefined",
    [0x0701] = "Level Calibration Noise Source",
    [0x0702] = "Equalization Noise",
    [0x0704] = "DAT",
    [0x0705] = "DCC",
    [0x0706] = "MiniDisk",
    [0x0707] = "Analog Tape",
    [0x0708] = "Phonograph",
    [0x0709] = "VCR Audio",
    [0x070A] = "Video Disc Audio",
    [0x070B] = "DVD Audio",
    [0x070C] = "TV Tuner Audio",
    [0x070D] = "Satellite Receiver Audio",
    [0x070E] = "Cable Tuner Audio",
    [0x070F] = "DSS Audio",
    [0x0710] = "Radio Receiver",
    [0x0711] = "Radio Transmitter",
    [0x0712] = "Multi-track Recorder",
    [0x0713] = "Synthesizer",
}
_G.audio_category_types = {
    [0x00] = "Undef",
    [0x01] = "Desktop Speaker",
    [0x02] = "Home Theater",
    [0x03] = "Microphone",
    [0x04] = "Headset",
    [0x05] = "Telephone",
    [0x06] = "Converter",
    [0x07] = "Sound Recoder",
    [0x08] = "Io Box",
    [0x09] = "Musical Instrument",
    [0x0a] = "Pro Audio",
    [0x0b] = "Audio Video",
    [0x0c] = "Control Panel",
    [0xff] = "Other",
}
_G.audio_process_types = {
    [0x00] = "PROCESS_UNDEFINED",
    [0x01] = "UP/DOWNMIX_PROCESS",
    [0x02] = "DOLBY_PROLOGIC_PROCESS",
    [0x03] = "3D_STEREO_EXTENDER_PROCESS",
}
_G.audio_clock_types = {
    [0x00] = "External Clock",
    [0x01] = "Internal fixed Clock",
    [0x02] = "Internal variable Clock",
    [0x03] = "Internal programmable Clock",
}
_G.audio_control_types = {
    [0x00] = "None",
    [0x01] = "Read",
    [0x03] = "Read_Write",
}

local audio_ac_interface  = {
    [0x01] = make_ac_interface("Header", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint16_t  bcdADC;
        uint8_t   bCategory;            // _G.audio_category_types
        uint16_t  wTotalLength;
        // bmControls
        uint8_t   Latency_Control:2;
        uint8_t   reserved:6;
    ]]),
    [0x02] = make_ac_interface("Input Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.audio_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   bCSourceID;
        uint8_t   bNrChannels;
        // bmChannelConfig
        uint32_t  Front_Left:1;
        uint32_t  Front_Right:1;
        uint32_t  Front_Center:1;
        uint32_t  Low_Frq_Effects:1;
        uint32_t  Back_Left:1;
        uint32_t  Back_Right:1;
        uint32_t  Front_Left_Of_Center:1;
        uint32_t  Front_Right_Of_Center:1;
        uint32_t  Back_Center:1;
        uint32_t  Side_Left:1;
        uint32_t  Side_Right:1;
        uint32_t  Top_Center:1;
        uint32_t  Top_Front_Left:1;
        uint32_t  Top_Front_Center:1;
        uint32_t  Top_Front_Right:1;
        uint32_t  Top_Back_Left:1;
        uint32_t  Top_Back_Center:1;
        uint32_t  Top_Back_Right:1;
        uint32_t  Top_Front_Left_Of_Center:1;
        uint32_t  Top_Front_Right_Of_Center:1;
        uint32_t  Left_Low_Frq_Effects:1;
        uint32_t  Right_Low_Frq_Effects:1;
        uint32_t  Top_Side_Left:1;
        uint32_t  Top_Side_Right:1;
        uint32_t  Bottom_Center:1;
        uint32_t  Back_Left_Of_Center:1;
        uint32_t  Back_Right_Of_Center:1;
        uint32_t  Raw_Data:1;
        uint8_t   iChannelNames;
        // bmControls
        uint16_t  Copy_Protect_Control:2;   // _G.audio_control_types
        uint16_t  Connector_Control:2;      // _G.audio_control_types
        uint16_t  Overload_Control:2;       // _G.audio_control_types
        uint16_t  Cluster_Control:2;        // _G.audio_control_types
        uint16_t  Underflow_Control:2;      // _G.audio_control_types
        uint16_t  Overflow_Control:2;       // _G.audio_control_types
        uint16_t  reserved:4;
        uint8_t   iTerminal;
    ]]),
    [0x03] = make_ac_interface("Output Terminal", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bTerminalID;
        uint16_t  wTerminalType;       // _G.audio_terminal_types
        uint8_t   bAssocTerminal;
        uint8_t   bSourceID;
        uint8_t   bCSourceID;
        // bmControls
        uint16_t  Copy_Protect_Control:2;   // _G.audio_control_types
        uint16_t  Connector_Control:2;      // _G.audio_control_types
        uint16_t  Overload_Control:2;       // _G.audio_control_types
        uint16_t  Cluster_Control:2;        // _G.audio_control_types
        uint16_t  Underflow_Control:2;      // _G.audio_control_types
        uint16_t  Overflow_Control:2;       // _G.audio_control_types
        uint16_t  reserved:4;
        uint8_t   iTerminal;
    ]]),
    [0x04] = make_ac_interface("Mixer Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t   bNrChannels;
        // bmChannelConfig
        uint32_t  Front_Left:1;
        uint32_t  Front_Right:1;
        uint32_t  Front_Center:1;
        uint32_t  Low_Frq_Effects:1;
        uint32_t  Back_Left:1;
        uint32_t  Back_Right:1;
        uint32_t  Front_Left_Of_Center:1;
        uint32_t  Front_Right_Of_Center:1;
        uint32_t  Back_Center:1;
        uint32_t  Side_Left:1;
        uint32_t  Side_Right:1;
        uint32_t  Top_Center:1;
        uint32_t  Top_Front_Left:1;
        uint32_t  Top_Front_Center:1;
        uint32_t  Top_Front_Right:1;
        uint32_t  Top_Back_Left:1;
        uint32_t  Top_Back_Center:1;
        uint32_t  Top_Back_Right:1;
        uint32_t  Top_Front_Left_Of_Center:1;
        uint32_t  Top_Front_Right_Of_Center:1;
        uint32_t  Left_Low_Frq_Effects:1;
        uint32_t  Right_Low_Frq_Effects:1;
        uint32_t  Top_Side_Left:1;
        uint32_t  Top_Side_Right:1;
        uint32_t  Bottom_Center:1;
        uint32_t  Back_Left_Of_Center:1;
        uint32_t  Back_Right_Of_Center:1;
        uint32_t  Raw_Data:1;
        uint8_t   iChannelNames;
        {
            uint8_t   bmMixerControls;
        }[ math.floor(bNrChannels* bNrInPins + 7 / 8) ];
        // bmControls
        uint8_t   Cluster_Control:2;        // _G.audio_control_types
        uint8_t   Underflow_Control:2;      // _G.audio_control_types
        uint8_t   Overflow_Control:2;       // _G.audio_control_types
        uint8_t   reserved:2;
        uint8_t   iMixer;
    ]]),
    [0x05] = make_ac_interface("Selector Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        // bmControls
        uint8_t   Selector_Control:2;       // _G.audio_control_types
        uint8_t   reserved:6;
        uint8_t   iSelector;
    ]]),
    [0x06] = make_ac_interface("Feature Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint8_t   bSourceID;
        {
            // bmaControl0
            uint32_t  Mute_Control:2;                // _G.audio_control_types
            uint32_t  Volume_Control:2;              // _G.audio_control_types
            uint32_t  Bass_Control:2;                // _G.audio_control_types
            uint32_t  Mid_Control:2;                 // _G.audio_control_types
            uint32_t  Treble_Control:2;              // _G.audio_control_types
            uint32_t  Graphic_Equalizer_Control:2;   // _G.audio_control_types
            uint32_t  Automatic_Gain_Control:2;      // _G.audio_control_types
            uint32_t  Delay_Control:2;               // _G.audio_control_types
            uint32_t  Bass_Boost_Control:2;          // _G.audio_control_types
            uint32_t  Loudness_Control:2;            // _G.audio_control_types
            uint32_t  Input_Gain_Control:2;          // _G.audio_control_types
            uint32_t  Input_Gain_Pad_Control:2;      // _G.audio_control_types
            uint32_t  Phase_Inverter_Control:2;      // _G.audio_control_types
            uint32_t  Underflow_Control:2;           // _G.audio_control_types
            uint32_t  Overfow_Control:2;             // _G.audio_control_types
            uint32_t  Reserved:2;
        };
        {
            uint32_t bmaControls;   // function(x) return toBits(x, 32) end
        }[ (bLength - 10) / 4 ];
        uint8_t   iFeature;
    ]]),
    [0x07] = make_ac_interface("Effect Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint16_t  wEffectType;         // _G.audio_process_types
        uint8_t   bSourceID;
        {
            uint32_t bmaControls;
        }[ (bLength - 16) / 4 + 2 ];
        uint8_t   iEffects;
    ]]),
    [0x08] = make_ac_interface("Processing Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint16_t  wProcessType;         // _G.audio_process_types
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];

        uint8_t  bNrChannels;
        // bmChannelConfig
        uint32_t  Front_Left:1;
        uint32_t  Front_Right:1;
        uint32_t  Front_Center:1;
        uint32_t  Low_Frq_Effects:1;
        uint32_t  Back_Left:1;
        uint32_t  Back_Right:1;
        uint32_t  Front_Left_Of_Center:1;
        uint32_t  Front_Right_Of_Center:1;
        uint32_t  Back_Center:1;
        uint32_t  Side_Left:1;
        uint32_t  Side_Right:1;
        uint32_t  Top_Center:1;
        uint32_t  Top_Front_Left:1;
        uint32_t  Top_Front_Center:1;
        uint32_t  Top_Front_Right:1;
        uint32_t  Top_Back_Left:1;
        uint32_t  Top_Back_Center:1;
        uint32_t  Top_Back_Right:1;
        uint32_t  Top_Front_Left_Of_Center:1;
        uint32_t  Top_Front_Right_Of_Center:1;
        uint32_t  Left_Low_Frq_Effects:1;
        uint32_t  Right_Low_Frq_Effects:1;
        uint32_t  Top_Side_Left:1;
        uint32_t  Top_Side_Right:1;
        uint32_t  Bottom_Center:1;
        uint32_t  Back_Left_Of_Center:1;
        uint32_t  Back_Right_Of_Center:1;
        uint32_t  Raw_Data:1;
        uint8_t   iChannelNames;
        // bmControls
        uint16_t  Enable_Control:2;         // _G.audio_control_types
        uint16_t  Pross_Specific:14;
        uint8_t   iProcessing;
        uint8_t   processData[];
    ]]),
    [0x09] = make_ac_interface("Extension Unit", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bUnitID;
        uint16_t  wExtensionCode;
        uint8_t   bNrInPins;
        {
            uint8_t baSourceID;
        }[bNrInPins];
        uint8_t  bNrChannels;
        // bmChannelConfig
        uint32_t  Front_Left:1;
        uint32_t  Front_Right:1;
        uint32_t  Front_Center:1;
        uint32_t  Low_Frq_Effects:1;
        uint32_t  Back_Left:1;
        uint32_t  Back_Right:1;
        uint32_t  Front_Left_Of_Center:1;
        uint32_t  Front_Right_Of_Center:1;
        uint32_t  Back_Center:1;
        uint32_t  Side_Left:1;
        uint32_t  Side_Right:1;
        uint32_t  Top_Center:1;
        uint32_t  Top_Front_Left:1;
        uint32_t  Top_Front_Center:1;
        uint32_t  Top_Front_Right:1;
        uint32_t  Top_Back_Left:1;
        uint32_t  Top_Back_Center:1;
        uint32_t  Top_Back_Right:1;
        uint32_t  Top_Front_Left_Of_Center:1;
        uint32_t  Top_Front_Right_Of_Center:1;
        uint32_t  Left_Low_Frq_Effects:1;
        uint32_t  Right_Low_Frq_Effects:1;
        uint32_t  Top_Side_Left:1;
        uint32_t  Top_Side_Right:1;
        uint32_t  Bottom_Center:1;
        uint32_t  Back_Left_Of_Center:1;
        uint32_t  Back_Right_Of_Center:1;
        uint32_t  Raw_Data:1;
        uint8_t   iChannelNames;
        // bmControls
        uint8_t   Enable_Control:2;         // _G.audio_control_types
        uint8_t   Cluster_Control:2;        // _G.audio_control_types
        uint8_t   Underflow_Control:2;      // _G.audio_control_types
        uint8_t   Overflow_Control:2;       // _G.audio_control_types
        uint8_t   iExtension;
    ]]),
    [0x0A] = make_ac_interface("Clock Source", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bClockID;
        // bmAttributes
        uint8_t   Clock_Type:2;     // _G.audio_clock_types
        uint8_t   Sync_SOF:1;
        uint8_t   reserved:5;
        // bmControls
        uint8_t   Frequency_Control:2;      // _G.audio_control_types
        uint8_t   Validity_Control:2;       // _G.audio_control_types
        uint8_t   reserved:4;
        uint8_t   bAssocTerminal;
        uint8_t   iClockSource;

    ]]),
    [0x0B] = make_ac_interface("Clock Selector", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;   // _G.audio_interface_desc_type
        uint8_t   bClockID;
        uint8_t   bNrInPins;
        {
            uint32_t baCSourceID;
        }[ bNrInPins ];
        // bmControls
        uint8_t   Selector_Control:2;       // _G.audio_control_types
        uint8_t   reserved:6;
        uint8_t   iClockSelector;
    ]]),
}

-- audio format types: frmts20.pdf
_G.audio_format_type = {
    [0x0000] = "TYPEUNDEFINED",
    [0x0001] = "TYPE_I",
    [0x0002] = "TYPE_II",
    [0x0003] = "TYPE_IIII",
    [0x0081] = "EXT_TYPE_I",
    [0x0082] = "EXT_TYPE_II",
    [0x0083] = "EXT_TYPE_IIII",
}

_G.audio_format_type_1 = {
    [0x0000] = "TYPE_I_UNDEFINED",
    [0x0001] = "PCM",
    [0x0002] = "PCM8",
    [0x0004] = "IEEE_FLOAT",
    [0x0008] = "ALAW",
    [0x0010] = "MULAW",
    [0x80000000] = "RAW",
}

local audio_as_interface  = {
    [0x01] = make_as_interface("General", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bTerminalLink;
        // bmControls
        uint8_t   Active_Alternate_Setting_Control:2;      // _G.audio_control_types
        uint8_t   Valid_Alternate_Settings_Control:2;      // _G.audio_control_types
        uint8_t   reserved:4;
        uint8_t   bFormatType;          // _G.audio_format_type
        uint32_t  bmFormats;
        uint8_t   bNrChannels;
        // bmChannelConfig
        uint32_t  Front_Left:1;
        uint32_t  Front_Right:1;
        uint32_t  Front_Center:1;
        uint32_t  Low_Frq_Effects:1;
        uint32_t  Back_Left:1;
        uint32_t  Back_Right:1;
        uint32_t  Front_Left_Of_Center:1;
        uint32_t  Front_Right_Of_Center:1;
        uint32_t  Back_Center:1;
        uint32_t  Side_Left:1;
        uint32_t  Side_Right:1;
        uint32_t  Top_Center:1;
        uint32_t  Top_Front_Left:1;
        uint32_t  Top_Front_Center:1;
        uint32_t  Top_Front_Right:1;
        uint32_t  Top_Back_Left:1;
        uint32_t  Top_Back_Center:1;
        uint32_t  Top_Back_Right:1;
        uint32_t  Top_Front_Left_Of_Center:1;
        uint32_t  Top_Front_Right_Of_Center:1;
        uint32_t  Left_Low_Frq_Effects:1;
        uint32_t  Right_Low_Frq_Effects:1;
        uint32_t  Top_Side_Left:1;
        uint32_t  Top_Side_Right:1;
        uint32_t  Bottom_Center:1;
        uint32_t  Back_Left_Of_Center:1;
        uint32_t  Back_Right_Of_Center:1;
        uint32_t  Raw_Data:1;
        uint8_t   iChannelNames;
    ]]),

    [0x1001] = make_as_interface("Format Type I", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint8_t   bSubslotSize;         // {format = "dec"}
        uint8_t   bBitResolution;       // {format = "dec"}
    ]]),
    [0x1002] = make_as_interface("Format Type II", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint16_t  wMaxBitRate;          // {format = "dec"}
        uint16_t  wSlotsPerFrame;       // {format = "dec"}
    ]]),
    [0x1003] = make_as_interface("Format Type III", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint8_t   bSubslotSize;         // {format = "dec"}
        uint8_t   bBitResolution;       // {format = "dec"}
    ]]),
    [0x1004] = make_as_interface("Format Type IV", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
    ]]),
    [0x1081] = make_as_interface("EXT Format Type I", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint8_t   bSubslotSize;         // {format = "dec"}
        uint8_t   bBitResolution;       // {format = "dec"}
        uint8_t   bHeaderLength;
        uint8_t   bControlSize;
        uint8_t   bSideBandProtocol;
    ]]),
    [0x1082] = make_as_interface("EXT Format Type II", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint16_t  wMaxBitRate;          // {format = "dec"}
        uint16_t  wSlotsPerFrame;       // {format = "dec"}
        uint8_t   bHeaderLength;
        uint8_t   bSideBandProtocol;
    ]]),
    [0x1083] = make_as_interface("EXT Format Type III", [[
        uint8_t   bLength;
        uint8_t   bDescriptorType;      // CS_INTERFACE
        uint8_t   bDescriptorSubtype;
        uint8_t   bFormatType;
        uint8_t   bSubslotSize;         // {format = "dec"}
        uint8_t   bBitResolution;       // {format = "dec"}
        uint8_t   bHeaderLength;
        uint8_t   bSideBandProtocol;
    ]]),
}

local struct_cs_audio_data_endpoint = html.create_struct([[
    uint8_t   bLength;
    uint8_t   bDescriptorType;      // CS_ENDPOINT
    uint8_t   bDescriptorSubtype;
    // bmAttributes
    uint8_t   reserved:7;
    uint8_t   MaxPacketsOnly:1;
    // bmControls
    uint8_t   Pitch_Control:2;          // _G.audio_control_types
    uint8_t   Data_Overrun_Control:2;   // _G.audio_control_types
    uint8_t   Data_Underrun_Control:2;  // _G.audio_control_types
    uint8_t   reserved:2;
    uint8_t   bLockDelayUnits; // {[0] = "undefined", [1] = "Milliseconds", [2] = "Decoded PCM samples"}
    uint16_t  wLockDelay;
]])

local selector_map = {}
selector_map[0x02] = {
    name = "Terminal Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t terminal_id:8;
        }
    ]],
    wValue_info = {
        selector = {
                [0x01] = "Copy_Protect_Control",
                [0x02] = "Connector_Control"
        }},
    data = function(setup)
        local info = select(setup.wValue >> 8
                ,"uint8_t bCopyProtect; // {[0] = 'CPL0', [1] = 'CPL1', [2] = 'CPL2'}"
                ,"uint8_t  bNrChannels;\n" ..
                 "uint32_t bmChannelConfig;\n" ..
                 "uint8_t iChannelNames;"
            )
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Terminal Control Data").html
        end
    end
}
selector_map[0x03] = selector_map[0x02]
selector_map[0x04] = {
    name = "Mixer Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t MCN:8; // Mixer Control Number
            uint16_t CS:8;  // MU_MIXER_CONTROL
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    data = function(setup)
        local info = "int16_t wMixer; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end"
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Mixer Unit Control Data").html
        end
    end,
    data_range = function(setup)
        local info = "uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
                     "{\nint16_t wMIN; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
                     "int16_t wMAX; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
                     "int16_t wRES; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
                     "\n}[wNumSubRanges];"
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Mixer Unit Control Data").html
        end
    end
}
selector_map[0x05] = {
    name = "Selector Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    data = function(setup)
        return function(data)
            return html.create_struct([[
                uint8_t bSelector;
            ]]):build(data, "Selector Control Data").html
        end
    end
}

selector_map[0x06] = {
    name = "Feature Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Mute_Control",
            [0x02] = "Volume_Control",
            [0x03] = "Bass_Control",
            [0x04] = "Mid_Control",
            [0x05] = "Treble_Control",
            [0x06] = "Graphic_Equalizer_Control",
            [0x07] = "Automatic_Gain_Control",
            [0x08] = "Delay_Control",
            [0x09] = "Bass_Boost_Control",
            [0x0a] = "Loudness_Control",
            [0x0b] = "Input_Gain_Control",
            [0x0c] = "Input_Gain_Pad_Control",
        }
    },
    data = function(setup)
        local info = select(setup.wValue >> 8
            ,"uint8_t bMute;  // {[0]='false', [1] = 'true'}"
            ,"int16_t wVolume; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) .. ' dB' end"
            ,"int8_t  bBase;   // function(x) return string.format(\"%.2f\",x*(31.75/127)) .. ' dB' end"
            ,"int8_t  bMid;   // function(x) return string.format(\"%.2f\",x*(31.75/127)) .. ' dB' end"
            ,"int8_t  bTreble;   // function(x) return string.format(\"%.2f\",x*(31.75/127)) .. ' dB' end"
            ,"uint32_t bmBandsPresent;\n" ..
                "{\nint8_t  bBand; // function(x) return string.format(\"%.2f\",x*(31.75/127)) .. ' dB' end \n}[" .. (setup.wLength-4) .. "];"
            ,"uint8_t  bAGC;   // {[0]='false', [1] = 'true'}"
            ,"uint32_t dwDelay;   // function(x) return string.format(\"%.2f\",x*(1/4194)) ..' ms' end"
            ,"uint8_t  bBassBoost;   // {[0]='false', [1] = 'true'}"
            ,"uint8_t  bLoudness;   // {[0]='false', [1] = 'true'}"
            ,"int16_t  wGain; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) .. ' dB' end"
            ,"int16_t  wGainPad; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) .. ' dB' end"
        )
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Feature Unit Control Data").html
        end
    end,
    data_range = function(setup)
        local info = select(setup.wValue >> 8
            ,""
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint16_t wVolumeMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int16_t wVolumeMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint16_t wVolumeRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint8_t bBaseMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int8_t bBaseMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint8_t bBaseRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint8_t bMidMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int8_t bMidMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint8_t bMidRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint8_t bTrebleMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int8_t bTrebleMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint8_t bTrebleRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint8_t bEQMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int8_t bEQMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint8_t bEQRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,""
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint32_t dwDelayMin; // function(x) return string.format(\"%.2f\",x*(1/4194)) ..' ms' end\n" ..
            "int32_t dwDelayMax; // function(x) return string.format(\"%.2f\",x*(1/4194)) ..' ms' end\n" ..
            "uint32_t dwDelayRes; // function(x) return string.format(\"%.2f\",x*(1/4194)) ..' ms' end\n" ..
            "\n}[wNumSubRanges];"
            ,""
            ,""
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint16_t wGainMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int16_t wGainMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint16_t wGainRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nint16_t wGainPadMin; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "int16_t wGainPadMax; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "uint16_t wGainPadRes; // function(x) return string.format(\"%.2f\",x*(127.9961/32767)) ..' db' end\n" ..
            "\n}[wNumSubRanges];"
        )
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Feature Unit Control Data").html
        end
    end
}

selector_map[0x09] = {
    name = "Extension Unit Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Xu_Enable_Control",
        }
    },
    data = function(setup)
        return function(data)
            return html.create_struct([[
                uint8_t bOn; // {[0] = 'false', [1] = 'true'
            ]]):build(data, "Extension Control Data").html
        end
    end
}

selector_map[0x0A] = {
    name = "Clock Source Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Sampling_Frequency_Control",
            [0x02] = "Clock_Validity_Control",
        }
    },
    data = function(setup)
        local info = select(setup.wValue >> 8
            ,"uint32_t dwFrequency;  // {format = 'dec', comment = 'Hz'}"
            ,"uint8_t  bValidity;    // {[0]='false', [1] = 'true'}"
        )
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Clock Source Control Data").html
        end
    end,
    data_range = function(setup)
        local info = select(setup.wValue >> 8
            ,"uint16_t wNumSubRanges; // {format = 'dec'}\n" ..
            "{\nuint32_t dwFrequencyMin; // {format = 'dec', comment = 'Hz'}\n" ..
            "uint32_t dwFrequencyMax; // {format = 'dec', comment = 'Hz'}\n" ..
            "uint32_t dwFrequencyRes; // {format = 'dec', comment = 'Hz'}\n" ..
            "\n}[wNumSubRanges];"
            ,""

        )
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Clock Source Control Data").html
        end
    end
}

selector_map[0x0B] = {
    name = "Clock Selector Control",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Clock_Selector_Control",
        }
    },
    data = function(setup)
        local info = "uint8_t bClock;"
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Clock Selector Control Data").html
        end
    end,
}

local processor_selector_map = {}
processor_selector_map[0x01] = {
    name = "UP/DOWNMIX_PROCESS",
    wValue = [[
        struct{
            // wValue
            uint16_t CN:8;          // Channel Number
            uint16_t CS:8;          // Control Selector
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t interface:8;
            uint16_t unit_id:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Ud_Enable_Control",
            [0x02] = "Ud_Mode_Select_Control",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
        elseif sel == 2 then
            info = "uint8_t  bMode;"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
        end
    end
}
processor_selector_map[0x02] = processor_selector_map[0x01]
processor_selector_map[0x02].name = "DOLBY_PROLOGIC_PROCESS"
processor_selector_map[0x02].wValue_info = {
    selector = {
        [0x01] = "Db_Enable_Control",
        [0x02] = "Db_Mode_Select_Control",
    }
}

processor_selector_map[0x03] = processor_selector_map[0x01]
processor_selector_map[0x03].name = "3D_STEREO_EXTENDER_PROCESS"
processor_selector_map[0x03].wValue_info = {
    selector = {
        [0x01] = "3d_Enable_Control",
        [0x02] = "Spaciousness_Control",
    }
}
processor_selector_map[0x03].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bSpaciousness;"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x04] = processor_selector_map[0x01]
processor_selector_map[0x04].name = "REVERBERATION_PROCESS"
processor_selector_map[0x04].wValue_info = {
    selector = {
        [0x01] = "Rv_Enable_Control",
        [0x02] = "Reverb_Level_Control",
        [0x03] = "Reverb_Time_Control",
        [0x04] = "Reverb_Feedback_Control",
    }
}
processor_selector_map[0x04].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bReverbLevel;"
    elseif sel == 3 then
        info = "uint16_t  wReverbTime; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' s' end"
    elseif sel == 4 then
        info = "uint8_t  bReverbFeedback;"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x05] = processor_selector_map[0x01]
processor_selector_map[0x05].name = "CHORUS_PROCESS"
processor_selector_map[0x05].wValue_info = {
    selector = {
        [0x01] = "Ch_Enable_Control",
        [0x02] = "Chorus_Level_Control",
        [0x03] = "Chorus_Rate_Control",
        [0x04] = "Chorus_Depth_Control",
    }
}
processor_selector_map[0x05].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint8_t  bChorusLevel;"
    elseif sel == 3 then
        info = "uint16_t  wChorusRate; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' Hz' end"
    elseif sel == 4 then
        info = "uint16_t  wChorusDepth; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' ms' end"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

processor_selector_map[0x06] = processor_selector_map[0x01]
processor_selector_map[0x06].name = "DYN_RANGE_COMP_PROCESS"
processor_selector_map[0x06].wValue_info = {
    selector = {
        [0x01] = "DR_Enable_Control",
        [0x02] = "Compression_Rate_Control",
        [0x03] = "Maxampl_Control",
        [0x04] = "Threshold_Control",
        [0x05] = "Attack_Time",
        [0x06] = "Release_Time",
    }
}
processor_selector_map[0x06].data = function(setup)
    local sel = setup.wValue >> 8
    local info = ""
    if sel == 1 then
        info = "uint8_t  bEnable;   // {[0]='false', [1] = 'true'}"
    elseif sel == 2 then
        info = "uint16_t  wRatio; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' dB' end"
    elseif sel == 3 then
        info = "int16_t  wMaxAmpl; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' dB' end"
    elseif sel == 4 then
        info = "int16_t  wThreshold; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' dB' end"
    elseif sel == 5 then
        info = "uint16_t  wAttackTime; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' ms' end"
    elseif sel == 6 then
        info = "uint16_t  wAttackTime; // function(x) return string.format(\"%.2f\",x*(1/256)) .. ' ms' end"
    end
    return function(data)
        return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Process Data").html
    end
end

local stream_selector_map = {}

local ep_control_selector_map = {
    name = "Endpoint Control",
    wValue = [[
        struct{
            // wValue
            uint16_t zero:8;
            uint16_t selector:8;
        }
    ]],
    wIndex = [[
        struct{
            // wIndex
            uint16_t endpoint:8;
            uint16_t zero:8;
        }
    ]],
    wValue_info = {
        selector = {
            [0x01] = "Pitch_Control",
            [0x02] = "Overrun_Control",
            [0x03] = "Underrun_Control",
        }
    },
    data = function(setup)
        local sel = setup.wValue >> 8
        local info = ""
        if sel == 1 then
            info = "uint8_t  bPitchEnable;  // {[0]='false', [1] = 'true'}"
        elseif sel == 2 then
            info = "uint8_t  bOverrun;  // {[0]='false', [1] = 'true'}"
        elseif sel == 3 then
            info = "uint8_t  bUnderrun;  // {[0]='false', [1] = 'true'}"
        end
        return function(data)
            return html.create_struct("struct {\n" .. info .. "\n}"):build(data, "Endpoint Control Data").html
        end
    end
}

local audio_interrupt_data = html.create_struct([[
    // bInfo
    uint8_t  Type:1;          // {[0]="Class-Specific", [1]="Vendor-Specficic"}
    uint8_t  IntfEp:1;        // {[0]="Interface", [1]="Endpoint"}
    uint8_t  Reserved:6;
    uint8_t  bAttribute;      // {[0]="Undefined", [1]="Current", [2]="Range", [3]="Mem"}
    struct{
        // wValue
        uint8_t CN_MCN;
        uint8_t ControlSelector;
    };
    struct{
        // wIndex
        uint8_t EP_Intf;
        uint8_t EntityID;
    };
]])

audio_render_selector = function(setup, context)
    local s = nil
    local sel = setup.wValue >> 8
    if setup.type == "Class" and setup.recip == "Endpoint"  then
        setup.audio_data_render = nil
        s = ep_control_selector_map
    end
    if not s then
        local id = setup.wIndex >>8
        local itf = setup.wIndex & 0xff
        local itf_data = context:get_interface_data(itf)
        setup.audio_data_render = nil
        if itf_data.audio_selector and itf_data.audio_selector[id] then
            s = itf_data.audio_selector[id]
        end
    end
    if s then
        local desc = s.wValue_info and s.wValue_info.selector and s.wValue_info.selector[sel]
        setup.render.wValue = html.create_field(s.wValue, s.wValue_info)
        setup.render.wIndex = html.create_field(s.wIndex)
        setup.render.title = setup.render.title .. " (" .. s.name .. " - " .. desc ..")"
        if setup.bRequest == 2 then
            setup.audio_data_render = s.data_range(setup)
        else
            setup.audio_data_render = s.data(setup)
        end
    end
end

local function ac_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    local id = data:byte(offset + 3)
    local processType = data:byte(offset + 4)
    local itf_data = context:current_interface_data()
    itf_data.audio_selector = itf_data.audio_selector or {}
    if subType == 8 then
        -- process unit
        itf_data.audio_selector[id] = processor_selector_map[processType]
    elseif subType > 1 then
        if selector_map[subType] then
            itf_data.audio_selector[id] = selector_map[subType]
        end
    end
end

local function as_parse_selector(data, offset, context)
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    local itf_data = context:current_interface_data()
    itf_data.audio_selector = itf_data.audio_selector or {}
    if stream_selector_map[subType] then
        itf_data.audio_selector[id] = stream_selector_map[subType]
    end
end

local function as_descriptpr_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    local itf_data = context:current_interface_data()

    if t == macro_defs.CS_ENDPOINT then
        if #data >= offset+len+6 then
            local bEndpointAddress = data:byte(offset + len + 2)
            local bmAttributes = data:byte(offset + len + 3)
            if bmAttributes == 0x11 then
                itf_data.ep_fb = bEndpointAddress
            end
        end
        return struct_cs_audio_data_endpoint:build(data:sub(offset), "CS Endpoint Descriptor")
    end
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end

    if subType == 1 then
        itf_data.bFormatType = data:byte(offset+5)
        itf_data.bmFormats = data:byte(offset+6)
    end
    if subType == 2 and itf_data.bFormatType then
        if audio_as_interface[itf_data.bFormatType + 0x1000] then
            if itf_data.bFormatType == 1 then
                local bSubslotSize = data:byte(offset+4)
                itf_data.decoderMap = itf_data.decoderMap or {}
                itf_data.decoderMap[#itf_data.decoderMap+1]=itf_data.bmFormats * 256 + bSubslotSize
            end
            return audio_as_interface[itf_data.bFormatType + 0x1000](data, offset, context)
        end
    end
    as_parse_selector(data, offset, context)
    return audio_as_interface[subType] and audio_as_interface[subType](data, offset, context)
end

local function ac_descriptor_parser(data, offset, context)
    local len = data:byte(offset)
    if #data < offset+len then return end
    local t = data:byte(offset + 1)
    local subType = data:byte(offset + 2)
    if t == macro_defs.ENDPOINT_DESC and len == 7 then
        return struct_audio_sync_endpoint_desc:build(data:sub(offset), "Endpoint Descriptor")
    end
    if t ~= macro_defs.CS_INTERFACE then
        return nil
    end
    ac_parse_selector(data, offset, context)
    return audio_ac_interface[subType] and audio_ac_interface[subType](data, offset, context)
end

local function ctrl_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if needDetail then
        local status = "success"
        local html = audio_interrupt_data:build(data, "Audio Interrupt Message").html
        local audio_format = req2str[data:byte(2)]
        local t = self:get_endpoint_interface_data(addr, ep)
        local title = "Audio Notification"
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Audio Notification", html, data), self.upv.make_xfer_res({
            title = title,
            name  = "Audio Notif",
            desc  = audio_format,
            status = status,
            infoHtml = html,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

local function data_on_transaction(self, param, data, needDetail, forceBegin)
    local addr, ep, pid, ack = param:byte(1), param:byte(2), param:byte(3), param:byte(4)
    if needDetail then
        local status = "success"
        local name  = "Audio Format"
        local html = "<h1>Audio Data</h1>"
        local audio_format = "Unknown"
        local t = self:get_endpoint_interface_data(addr, ep)
        local title
        if t.ep_fb and ep == t.ep_fb then
            title = "Audio Feedback"
            name = "Feedback Format"
            if #data == 3 then
                audio_format = "10.14"
                html = "<h1>" .. string.format("%.6f" ,unpack("<I3", data) / 16384) .. " kHz </h1>"
            elseif #data == 4 then
                audio_format = "16.16"
                html = "<h1>" .. string.format("%.6f", unpack("<I4", data) / 65536) .. " kHz </h1>"
            end
        else
            local decoderId = t.alt_setting and t.decoderMap and t.decoderMap[t.alt_setting]
            local audio_frame_decoder = decoderId and audio_as_decoder[decoderId]
            if audio_frame_decoder then
                audio_format = audio_frame_decoder.name
                html = audio_frame_decoder.decode(data, self)
            end
            title = "Audio Out"
            if ep > 127 then
                title = "Audio In"
            end
        end
        return macro_defs.RES_BEGIN_END, self.upv.make_xact_res("Audio Stream", html, data), self.upv.make_xfer_res({
            title = title,
            name  = name,
            desc  = audio_format,
            status = status,
            infoHtml = html,
            data = data,
        })
    end
    return macro_defs.RES_BEGIN_END
end

cls.bInterfaceClass     = 1
cls.bInterfaceSubClass  = 1
cls.bInterfaceProtocol  = 0x20
-- register endpoint for both direction

local subClassName = {
    [0x01] ="Audio Control"    ,
    [0x02] ="Audio Streaming"  ,
}
function cls.get_name(desc, context)
    local name = subClassName[desc.bInterfaceSubClass] or "UNDEFINED"
    return {
        bInterfaceClass = "Audio",
        bInterfaceSubClass = name,
        bInterfaceProtocol = "2.0",
    }
end

local reg_audio = function(subCls, eps)
    local t = {}
    for k,v in pairs(cls) do
        t[k] = v
    end
    t.bInterfaceSubClass = subCls
    register_class_handler(t)
end

cls.name = "Audio 2.0 Control"
cls.descriptor_parser = ac_descriptor_parser
cls.on_transaction = ctrl_on_transaction
cls.endpoints = { EP_IN("Control Data",true)}
reg_audio(1)

cls.name = "Audio 2.0 Data"
cls.descriptor_parser = as_descriptpr_parser
cls.on_transaction = data_on_transaction
cls.endpoints = { EP_IN("Incoming Data",true), EP_OUT("Outgoning Data",true) }
reg_audio(2)

-- for interface in IAD
cls.iad = {
    bInterfaceClass     = 1,
    bFunctionProtocol   = 0x20,
}

cls.name = "Audio 2.0 Control"
cls.descriptor_parser = ac_descriptor_parser
cls.on_transaction = ctrl_on_transaction
cls.endpoints = { EP_IN("Control Data",true)}
reg_audio(1)

cls.name = "Audio 2.0 Data"
cls.descriptor_parser = as_descriptpr_parser
cls.on_transaction = data_on_transaction
cls.endpoints = { EP_IN("Incoming Data",true), EP_OUT("Outgoning Data",true) }
reg_audio(2)

package.loaded["usb_class_audio2"] = cls
