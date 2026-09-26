module("luci.controller.wisp", package.seeall)

function index()
	entry({"admin", "network", "wisp"}, call("action_page"), _("Смена Wi‑Fi"), 45).dependent = false
end

local function sh_quote(s)
	s = s or ""
	return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function read_status()
	local st = { ssid5 = "", ssid24 = "", up5 = "0", up24 = "0", tunnel = "down", handshake_age = "99999" }
	local fd = io.popen("/usr/libexec/wisp-switch.sh status 2>/dev/null")
	if not fd then return st end
	for line in fd:lines() do
		local k, v = line:match("^([^=]+)=(.*)$")
		if k and st[k] ~= nil then st[k] = v end
	end
	fd:close()
	return st
end

local function read_scan()
	local list = {}
	local fd = io.popen("/usr/libexec/wisp-switch.sh scan 2>/dev/null")
	if not fd then return list end
	for line in fd:lines() do
		local band, channel, signal, enc, ssid = line:match("^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$")
		if ssid and ssid ~= "" then
			list[#list + 1] = {
				band = band,
				channel = channel,
				signal = signal,
				enc = enc,
				ssid = ssid,
			}
		end
	end
	fd:close()
	return list
end

function action_page()
	local http = require "luci.http"
	local tpl = require "luci.template"
	local sys = require "luci.sys"

	local msg, err
	local do_scan = http.formvalue("scan")
	local do_apply = http.formvalue("apply")
	local choice = http.formvalue("choice") or ""
	local key = http.formvalue("key") or ""
	local networks = {}
	local picked = ""

	local band, ssid = choice:match("^(%d+):::(.*)$")
	if ssid then
		picked = ssid
	end

	if do_apply and ssid and ssid ~= "" then
		local cmd = string.format(
			"WISP_SSID=%s WISP_KEY=%s WISP_BAND=%s /usr/libexec/wisp-switch.sh apply 2>&1",
			sh_quote(ssid), sh_quote(key), sh_quote(band or "auto")
		)
		local out = sys.exec(cmd) or ""
		if out:find("applied_ssid=", 1, true) then
			msg = "Подключено к «" .. ssid .. "». Туннель поднимается сам (обычно 10–30 с). Обновите страницу через полминуты."
		else
			err = "Не удалось подключиться. Проверьте пароль и зону покрытия."
			local tail = out:gsub("\n", " "):sub(1, 240)
			if tail ~= "" then err = err .. " (" .. tail .. ")" end
		end
	elseif do_scan then
		networks = read_scan()
		if #networks == 0 then
			err = "Сети не найдены. Подойдите ближе или нажмите «Найти сети» ещё раз."
		end
	end

	-- после apply тоже показать свежий список по желанию — не сканируем снова (долго)
	if do_apply then
		networks = {}
	end

	tpl.render("wisp/switch", {
		status = read_status(),
		networks = networks,
		msg = msg,
		err = err,
		picked = picked,
	})
end
