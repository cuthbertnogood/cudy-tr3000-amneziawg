'use strict';
'require view';
'require fs';
'require ui';
'require dom';

function parseStatus(text) {
	var st = { ssid5: '', ssid24: '', up5: '0', up24: '0', tunnel: 'down', handshake_age: '99999' };
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

return view.extend({
	load: function() {
		return fs.exec('/usr/libexec/wisp-switch.sh', ['status']).then(function(res) {
			return parseStatus(res.stdout || '');
		}).catch(function() {
			return parseStatus('');
		});
	},

	renderStatusBox: function(st) {
		var tunOk = st.tunnel === 'up';
		return E('div', { 'class': 'cbi-section', 'style': 'padding:1rem;background:#f6f8fa;border-radius:6px;margin:1rem 0' }, [
			E('div', {}, [
				'Сейчас 5 ГГц: ', E('strong', {}, [st.ssid5 || '—']),
				' ', E('span', { 'style': st.up5 === '1' ? 'color:#1a7f37' : 'color:#cf222e' },
					[st.up5 === '1' ? '· онлайн' : '· нет связи'])
			]),
			E('div', {}, [
				'Сейчас 2,4 ГГц: ', E('strong', {}, [st.ssid24 || '—']),
				' ', E('span', { 'style': st.up24 === '1' ? 'color:#1a7f37' : 'color:#cf222e' },
					[st.up24 === '1' ? '· онлайн' : '· нет связи'])
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
			var el = document.getElementById('wisp-status');
			if (el)
				dom.content(el, [self.renderStatusBox(st)]);
		});
	},

	handleScan: function(ev) {
		var btn = ev.currentTarget;
		var box = document.getElementById('wisp-scan-box');
		var self = this;
		btn.disabled = true;
		dom.content(box, E('p', {}, [_('Сканирование…')]));
		return fs.exec('/usr/libexec/wisp-switch.sh', ['scan']).then(function(res) {
			var nets = parseScan(res.stdout || '');
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
					}, [_('Подключить и поднять VPN')])
				])
			]);
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
		var msg = document.getElementById('wisp-msg');
		var self = this;

		dom.content(msg, E('p', {}, [_('Подключаю… подождите несколько секунд')]));

		var cmd = 'WISP_SSID=' + shellQuote(ssid) +
			' WISP_KEY=' + shellQuote(key) +
			' WISP_BAND=' + shellQuote(band) +
			' /usr/libexec/wisp-switch.sh apply';

		return fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
			var out = (res && res.stdout) || '';
			var err = (res && res.stderr) || '';
			if (out.indexOf('applied_ssid=') >= 0) {
				dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
					_('Подключено к «%s». Туннель поднимается сам — обновите страницу через 20–30 с.').format(ssid)
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
		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [_('Смена Wi‑Fi для VPN')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Выберите чужую сеть, к которой подключится Cudy. Свои Travel-VPN не меняются. После подключения туннель поднимается сам.')
			]),
			E('div', { 'id': 'wisp-status' }, [this.renderStatusBox(status)]),
			E('div', { 'id': 'wisp-msg' }),
			E('div', { 'style': 'margin:1rem 0' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(this, 'handleScan')
				}, [_('Найти сети')])
			]),
			E('div', { 'id': 'wisp-scan-box' }, [
				E('p', {}, [_('Нажмите «Найти сети», выберите сеть, введите пароль и нажмите «Подключить».')])
			])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
