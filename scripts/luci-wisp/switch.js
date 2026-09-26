'use strict';
'require view';
'require fs';
'require ui';
'require dom';

function parseStatus(text) {
	var st = {
		ssid5: '', ssid24: '', dis5: '0', dis24: '0',
		up5: '0', up24: '0', mode: 'both', traffic: 'vpn', tunnel: 'down', handshake_age: '99999'
	};
	String(text || '').split(/\n/).forEach(function(line) {
		var m = line.match(/^([^=]+)=(.*)$/);
		if (m && st[m[1]] !== undefined)
			st[m[1]] = m[2];
	});
	return st;
}

function parseScan(text) {
	var list = [];
	String(text || '').split(/\n/).forEach(function(line) {
		if (!line)
			return;
		var parts = line.split('|');
		if (parts.length < 5)
			return;
		list.push({
			band: parts[0],
			channel: parts[1],
			signal: parts[2],
			enc: parts[3],
			ssid: parts.slice(4).join('|')
		});
	});
	return list;
}

function shellQuote(s) {
	return "'" + String(s).replace(/'/g, "'\\''") + "'";
}

function connectLabel(traffic) {
	return traffic === 'wisp' ? _('Подключить') : _('Подключить и поднять VPN');
}

function trafficLabel(traffic) {
	return traffic === 'wisp' ? _('обычный, без туннеля') : _('VPN');
}

function modeLabel(mode) {
	if (mode === '5')
		return 'только 5 ГГц';
	if (mode === '24')
		return 'только 2,4 ГГц';
	return 'оба (5 ГГц предпочтительнее)';
}

function bandStatus(st, band) {
	var dis = band === '5' ? st.dis5 : st.dis24;
	var up = band === '5' ? st.up5 : st.up24;
	var ssid = band === '5' ? st.ssid5 : st.ssid24;
	if (dis === '1')
		return { ssid: ssid || '—', text: '· выключен', color: '#57606a' };
	if (up === '1')
		return { ssid: ssid || '—', text: '· онлайн', color: '#1a7f37' };
	return { ssid: ssid || '—', text: '· нет связи', color: '#cf222e' };
}

return view.extend({
	load: function() {
		return fs.exec('/usr/libexec/wisp-switch.sh', ['status']).then(function(res) {
			return parseStatus(res.stdout || '');
		}).catch(function() {
			return parseStatus('');
		});
	},

	selectedMode: function() {
		var el = document.querySelector('input[name="wisp-mode"]:checked');
		return (el && el.value) || 'both';
	},

	renderStatusBox: function(st) {
		var tunOk = st.tunnel === 'up';
		var b5 = bandStatus(st, '5');
		var b24 = bandStatus(st, '24');
		return E('div', { 'class': 'cbi-section', 'style': 'padding:1rem;background:#f6f8fa;border-radius:6px;margin:1rem 0' }, [
			E('div', {}, [
				'Режим интернета: ', E('strong', {}, [trafficLabel(st.traffic || 'vpn')]),
				' · ',
				E('a', { 'href': '/cgi-bin/luci/admin/network/traffic-mode' }, [_('переключить')])
			]),
			E('div', {}, [
				'Режим uplink: ', E('strong', {}, [modeLabel(st.mode || 'both')])
			]),
			E('div', {}, [
				'Сейчас 5 ГГц: ', E('strong', {}, [b5.ssid]),
				' ', E('span', { 'style': 'color:' + b5.color }, [b5.text])
			]),
			E('div', {}, [
				'Сейчас 2,4 ГГц: ', E('strong', {}, [b24.ssid]),
				' ', E('span', { 'style': 'color:' + b24.color }, [b24.text])
			]),
			E('div', {}, [
				'Туннель VPN: ',
				E('span', { 'style': tunOk ? 'color:#1a7f37;font-weight:600' : 'color:#cf222e;font-weight:600' },
					[tunOk ? 'работает' : 'не поднят'])
			])
		]);
	},

	refreshStatus: function() {
		var self = this;
		return fs.exec('/usr/libexec/wisp-switch.sh', ['status']).then(function(res) {
			var st = parseStatus(res.stdout || '');
			self._traffic = st.traffic || 'vpn';
			var el = document.getElementById('wisp-status');
			if (el)
				dom.content(el, [self.renderStatusBox(st)]);
			var radio = document.querySelector('input[name="wisp-mode"][value="' + (st.mode || 'both') + '"]');
			if (radio)
				radio.checked = true;
		});
	},

	handleSetMode: function() {
		var mode = this.selectedMode();
		var msg = document.getElementById('wisp-msg');
		var self = this;
		dom.content(msg, E('p', {}, [_('Применяю режим…')]));
		var cmd = 'WISP_MODE=' + shellQuote(mode) + ' /usr/libexec/wisp-switch.sh set-mode';
		return fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
			var out = (res && res.stdout) || '';
			if (out.indexOf('applied_mode=') >= 0) {
				var note = (self._traffic === 'wisp')
					? _('Режим uplink: %s. Туннель не поднимается.')
					: _('Режим uplink: %s. Туннель подхватит uplink сам (10–30 с).');
				dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
					note.format(modeLabel(mode))
				]));
			} else {
				dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [
					_('Не удалось сменить режим.'), ' ', out
				]));
			}
			return self.refreshStatus();
		}).catch(function(err) {
			dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		});
	},

	handleScan: function(ev) {
		var btn = ev.currentTarget;
		var box = document.getElementById('wisp-scan-box');
		var self = this;
		btn.disabled = true;
		dom.content(box, E('p', {}, [_('Сканирование… обычно 20–40 с, не закрывайте страницу')]));

		var showResults = function(stdout) {
			var nets = parseScan(stdout || '');
			if (!nets.length) {
				dom.content(box, E('p', { 'style': 'color:#cf222e' },
					[_('Сети не найдены. Подойдите ближе и нажмите ещё раз.')]));
				return;
			}
			var rows = nets.map(function(n, i) {
				var id = 'wisp-n-' + i;
				var val = n.band + ':::' + n.ssid;
				var bandLabel = n.band === '5' ? '5 ГГц' : '2,4 ГГц';
				return E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td' }, [
						E('input', { 'type': 'radio', 'name': 'wisp-choice', 'id': id, 'value': val })
					]),
					E('td', { 'class': 'td' }, [
						E('label', { 'for': id }, [E('strong', {}, [n.ssid])])
					]),
					E('td', { 'class': 'td' }, [bandLabel]),
					E('td', { 'class': 'td' }, [n.signal + ' dBm']),
					E('td', { 'class': 'td' }, [n.enc])
				]);
			});
			dom.content(box, [
				E('p', { 'style': 'color:#57606a' }, [
					_('Подключение использует режим uplink сверху. Для работы только на 2,4 выберите «только 2,4 ГГц», иначе живой 5 ГГц останется в приоритете.')
				]),
				E('table', { 'class': 'table' }, [
					E('tr', { 'class': 'tr table-titles' }, [
						E('th', { 'class': 'th' }, ['']),
						E('th', { 'class': 'th' }, [_('Сеть')]),
						E('th', { 'class': 'th' }, [_('Диапазон')]),
						E('th', { 'class': 'th' }, [_('Сигнал')]),
						E('th', { 'class': 'th' }, [_('Защита')])
					])
				].concat(rows)),
				E('div', { 'style': 'margin:1rem 0;display:flex;gap:.75rem;flex-wrap:wrap;align-items:center' }, [
					E('label', {}, [
						_('Пароль сети '),
						E('input', { 'type': 'password', 'id': 'wisp-key', 'style': 'min-width:14rem', 'autocomplete': 'off' })
					]),
					E('button', {
						'class': 'btn cbi-button cbi-button-save',
						'click': ui.createHandlerFn(self, 'handleApply')
					}, [connectLabel(self._traffic)])
				])
			]);
		};

		var pollCount = 0;
		var poll = function() {
			return fs.read('/tmp/wisp-scan.state').then(function(res) {
				var state = String((res && res.data) || res || '').replace(/\s+/g, '') || 'idle';
				if (state === 'running' || state === 'idle') {
					pollCount++;
					if (pollCount > 50) {
						throw new Error(_('Скан слишком долгий. Нажмите «Найти сети» ещё раз.'));
					}
					dom.content(box, E('p', {}, [
						_('Сканирование… ') + Math.min(pollCount * 1.5, 40).toFixed(0) + ' / ~40 с'
					]));
					return new Promise(function(resolve) {
						window.setTimeout(resolve, 1500);
					}).then(poll);
				}
				if (state === 'error') {
					return fs.read('/tmp/wisp-scan.err').then(function(errRes) {
						throw new Error(_('Ошибка скана. ') + String((errRes && errRes.data) || errRes || ''));
					});
				}
				return fs.read('/tmp/wisp-scan.out').then(function(outRes) {
					showResults(String((outRes && outRes.data) || outRes || ''));
				});
			});
		};

		return fs.exec('/usr/libexec/wisp-switch.sh', ['scan-start']).then(function() {
			return new Promise(function(resolve) {
				window.setTimeout(resolve, 800);
			}).then(poll);
		}).catch(function(err) {
			dom.content(box, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		}).finally(function() {
			btn.disabled = false;
		});
	},

	handleApply: function() {
		var choice = document.querySelector('input[name="wisp-choice"]:checked');
		if (!choice) {
			ui.addNotification(null, E('p', {}, [_('Сначала выберите сеть')]), 'warning');
			return;
		}
		var parts = choice.value.split(':::');
		var band = parts[0];
		var ssid = parts.slice(1).join(':::');
		var key = (document.getElementById('wisp-key') || {}).value || '';
		var mode = this.selectedMode();
		/* Если режим «оба», а сеть 2,4 — предупреждаем, но уважаем выбор.
		   Если хотят гарантированно 2,4 — режим должен быть «только 2,4». */
		var msg = document.getElementById('wisp-msg');
		var self = this;

		dom.content(msg, E('p', {}, [_('Подключаю… подождите несколько секунд')]));

		var cmd = 'WISP_SSID=' + shellQuote(ssid) +
			' WISP_KEY=' + shellQuote(key) +
			' WISP_BAND=' + shellQuote(band) +
			' WISP_MODE=' + shellQuote(mode) +
			' /usr/libexec/wisp-switch.sh apply';

		return fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
			var out = (res && res.stdout) || '';
			var err = (res && res.stderr) || '';
			if (out.indexOf('applied_ssid=') >= 0) {
				dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
					_('Подключено к «%s», режим: %s. Обновите статус через 20–30 с.').format(ssid, modeLabel(mode))
				]));
			} else {
				dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [
					_('Не удалось. Проверьте пароль.'), ' ', out || err
				]));
			}
			return self.refreshStatus();
		}).catch(function(err) {
			dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		});
	},

	render: function(status) {
		var mode = status.mode || 'both';
		this._traffic = status.traffic || 'vpn';
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [_('Смена Wi‑Fi')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Чужой Wi‑Fi нужен и в обычном режиме, и в VPN. Смена сети не переключает режим интернета: '),
				E('a', { 'href': '/cgi-bin/luci/admin/network/traffic-mode' }, [_('Режим интернета')]),
				_('. При «оба» живой 5 ГГц всегда предпочтительнее 2,4.')
			]),
			E('div', { 'id': 'wisp-status' }, [this.renderStatusBox(status)]),
			E('div', { 'class': 'cbi-section', 'style': 'margin:1rem 0;padding:1rem;border:1px solid #d0d7de;border-radius:6px' }, [
				E('h3', {}, [_('Режим uplink')]),
				E('label', { 'style': 'display:block;margin:.35rem 0' }, [
					E('input', { 'type': 'radio', 'name': 'wisp-mode', 'value': '5', 'checked': mode === '5' ? 'checked' : null }),
					' ', _('Только 5 ГГц'), ' — 2,4 выключается'
				]),
				E('label', { 'style': 'display:block;margin:.35rem 0' }, [
					E('input', { 'type': 'radio', 'name': 'wisp-mode', 'value': '24', 'checked': mode === '24' ? 'checked' : null }),
					' ', _('Только 2,4 ГГц'), ' — 5 ГГц выключается (иначе 5 всегда в приоритете)'
				]),
				E('label', { 'style': 'display:block;margin:.35rem 0' }, [
					E('input', { 'type': 'radio', 'name': 'wisp-mode', 'value': 'both', 'checked': mode === 'both' ? 'checked' : null }),
					' ', _('Оба'), ' — failover: сначала 5 ГГц, при обрыве 2,4'
				]),
				E('div', { 'style': 'margin-top:.75rem' }, [
					E('button', {
						'class': 'btn cbi-button cbi-button-action',
						'click': ui.createHandlerFn(this, 'handleSetMode')
					}, [_('Применить режим')])
				])
			]),
			E('div', { 'id': 'wisp-msg' }),
			E('div', { 'style': 'margin:1rem 0' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleScan')
				}, [_('Найти сети')])
			]),
			E('div', { 'id': 'wisp-scan-box' }, [
				E('p', {}, [_('Нажмите «Найти сети», выберите сеть, введите пароль и нажмите «Подключить». Режим uplink берётся из блока выше.')])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
