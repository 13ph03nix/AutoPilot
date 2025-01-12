-- Load configurations
local yubikeyVPN = require("config.yubikey_otp_openvpn_autoconnect")

-- Function to monitor and ensure the listener is running
local function monitorOtpListener(listenerModule, checkInterval)
    hs.timer.doEvery(checkInterval, function()
        if not listenerModule.isRunning() then
            listenerModule.start()
        end
    end)
end

-- Start the OTP and VPN listener
yubikeyVPN.start()

-- Start monitoring the listener's status every 5 seconds
monitorOtpListener(yubikeyVPN, 5)