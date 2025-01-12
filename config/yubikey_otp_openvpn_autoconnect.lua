-- Author: 13ph03nix, a.k.a. fenix. https://github.com/13ph03nix
-- Date: 2025-01-12
-- Description: This script handles YubiKey OTP Detection and OpenVPN Connection.
-- License: MIT

local keychainAccountName = "autopilot.openvpn.connect" -- Replace with your account name in Keychain
local otpBuffer = "" -- Buffer to store the complete OTP
local otpTimer = nil -- Timer to determine when OTP input is complete
local eventtap = nil -- Eventtap listener for keypresses

-- Logging function
local function log(message)
    hs.console.printStyledtext("[yubikey-otp-openvpn-autoconnect]: " .. message)
end

-- Validate OTP format (basic validation, extend as needed)
local function isValidOtp(otp)
    -- Assume OTP is 44 alphanumeric characters
    return otp:match("^%w+$") and #otp == 44
end

-- Function to get a password from macOS Keychain
local function getPasswordFromKeychain(accountName)
    local command = string.format(
        "security find-generic-password -a '%s' -w 2>/dev/null",
        accountName
    )
    local output = hs.execute(command)
    if output then
        return output:gsub("%s+$", "") -- Trim trailing whitespace
    else
        log("Failed to retrieve password from Keychain.")
        return nil
    end
end

local function connectOpenVPNGUI(otp)
    local combinedPassword = getPasswordFromKeychain(keychainAccountName) .. otp

    -- Copy and modified from https://github.com/raycast/script-commands/blob/master/commands/apps/openvpn/connect-openvpn.applescript
    local appleScript = [[
        if application "OpenVPN Connect" is running then
            -- no op
        else
            tell application "OpenVPN Connect" to activate
            delay 2 -- wait for init
        end if
        
        ignoring application responses -- removes 5 sec delay (via caching?)
            tell application "System Events" to tell process "OpenVPN Connect" to click menu bar item 1 of menu bar 2
        end ignoring

        delay 0.2
        do shell script "killall System\\ Events"
        
        tell application "System Events" to tell process "OpenVPN Connect" to tell menu bar item 1 of menu bar 2
            click
            get menu items of menu 1
            try
                click menu item "Connect" of menu 1
                delay 0.5
                tell application "System Events"
                    delay 0.2
                    keystroke "]] .. combinedPassword .. [[" -- Type the combined password
                    delay 0.2
                    keystroke return -- Simulate pressing the Enter key to confirm
                end tell
            on error --menu item toggles between connect/disconnect
                key code 53 -- escape key to close menu
            end try
        end tell
    ]]

    local success, result = hs.osascript.applescript(appleScript)
    if success then
        log("OpenVPN connected successfully.")
    else
        log("Connection failed.")
    end
end

-- Start the event listener
local function startListener()
    if eventtap then
        eventtap:stop() -- Stop any existing listener
        log("Previous eventtap stopped.")
    end

    eventtap = hs.eventtap.new({hs.eventtap.event.types.keyDown}, function(event)
        local flags = event:getFlags() -- Modifier keys
        local character = event:getCharacters() -- The character produced

        -- Check if the key is a valid alphanumeric character
        if flags:containExactly({}) and character:match("%w") then
            otpBuffer = otpBuffer .. character -- Append to the OTP buffer

            -- Reset the timer
            if otpTimer then
                otpTimer:stop()
            end

            otpTimer = hs.timer.doAfter(0.5, function()
                -- Assume OTP is complete if no new input in 0.5 seconds
                if isValidOtp(otpBuffer) then
                    log("Valid OTP captured: " .. otpBuffer)
                    connectOpenVPNGUI(otpBuffer)
                end
                otpBuffer = "" -- Clear the buffer
            end)
        end
    end)

    eventtap:start()
    log("OTP Listener started: Listening for OTP inputs...")
end

-- Stop the event listener
local function stopListener()
    if eventtap then
        eventtap:stop()
        eventtap = nil
        log("OTP Listener stopped.")
    end
end

-- Return the module with control methods
local module = {}
module.start = startListener
module.stop = stopListener
module.restart = function()
    stopListener()
    startListener()
end
module.isRunning = function()
    return eventtap ~= nil
end

return module
