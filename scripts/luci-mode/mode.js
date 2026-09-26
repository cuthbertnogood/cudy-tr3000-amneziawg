'use strict';
'require view';
'require fs';
'require ui';
'require dom';

var REFRESH_MS = 5000;
var IMG = '/luci-static/resources/view/traffic-mode/';

function parseConnections(text) {
	var st = {
		mode: 'vpn',
		tunnel: 'down',
		wg_up: '0',
		handshake_age_human: '—',
		rx_human: '—',
		tx_human: '—',
		wwan5_up: '0',
		wwan24_up: '0',
		ssid5: '',
		ssid24: '',
		sig5: '',
		sig24: '',
		ip5: '',
		gw5: '',
		ip24: '',
		gw24: '',
		clients: []
	};
	String(text || '').split(/\n/).forEach(function(line) {
		if (!line)
			return;
		if (line.indexOf('client\t') === 0) {
			var p = line.split('\t');
			st.clients.push({
				name: p[1] || '—',
				ip: p[2] || '—',
				mac: p[3] || '—',
				medium: p[4] || '—',
				signal: p[5] || '',
				ssid: p[6] || ''
			});
			return;
		}
		var m = line.match(/^([^=]+)=(.*)$/);
		if (m && st[m[1]] !== undefined)
			st[m[1]] = m[2];
	});
	return st;
}

function uplinkRow(label, up, ssid, sig, ip, gw) {
	var on = up === '1';
	var bits = [];
	if (ssid)
		bits.push(ssid);
	if (sig)
		bits.push(sig + ' dBm');
	if (ip)
		bits.push(ip);
	if (gw)
		bits.push('шлюз ' + gw);
	return E('div', { 'style': 'display:flex;justify-content:space-between;gap:1rem;padding:.35rem 0;border-bottom:1px solid #eaeef2' }, [
		E('span', {}, [label]),
		E('span', { 'style': 'text-align:right' }, [
			E('strong', { 'style': 'color:' + (on ? '#1a7f37' : '#57606a') }, [on ? 'онлайн' : 'нет']),
			bits.length ? E('span', { 'style': 'color:#57606a' }, [' · ' + bits.join(' · ')]) : ''
		])
	]);
}

return view.extend({
	_timer: null,
	_busy: false,

	load: function() {
		return fs.exec('/usr/libexec/awg-mode.sh', ['connections']).then(function(res) {
			return parseConnections(res.stdout || '');
		}).catch(function() {
			return parseConnections('');
		});
	},

	card: function(mode, title, text, img, active) {
		var self = this;
		return E('button', {
			'type': 'button',
			'style': 'text-align:left;cursor:pointer;padding:0;border-radius:12px;overflow:hidden;background:#fff;width:100%;' +
				(active
					? 'border:2px solid #1a7f37;box-shadow:0 0 0 3px rgba(26,127,55,.12)'
					: 'border:1px solid #d0d7de'),
			'click': ui.createHandlerFn(self, 'handlePick', mode)
		}, [
			E('img', {
				'src': IMG + img,
				'alt': '',
				'style': 'display:block;width:100%;height:auto;background:#f6f8fa'
			}),
			E('div', { 'style': 'padding:.85rem 1rem 1rem' }, [
				E('div', { 'style': 'display:flex;justify-content:space-between;align-items:center;gap:.5rem' }, [
					E('strong', { 'style': 'font-size:1.05rem' }, [title]),
					active ? E('span', {
						'style': 'background:#dafbe1;color:#1a7f37;border-radius:999px;padding:.1rem .55rem;font-size:.8rem;font-weight:650'
					}, [_('Сейчас')]) : ''
				]),
				E('p', { 'style': 'margin:.45rem 0 0;color:#57606a;line-height:1.4' }, [text])
			])
		]);
	},

	renderStats: function(st) {
		var vpn = st.mode === 'vpn';
		var rows = st.clients.map(function(c) {
			return E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, [c.name]),
				E('td', { 'class': 'td' }, [c.ip]),
				E('td', { 'class': 'td' }, [c.medium + (c.ssid ? ' · ' + c.ssid : '')]),
				E('td', { 'class': 'td' }, [c.signal ? (c.signal + ' dBm') : '—']),
				E('td', { 'class': 'td', 'style': 'font-family:ui-monospace,monospace;font-size:.85em' }, [c.mac])
			]);
		});
		var clientBody = rows.length ? E('table', { 'class': 'table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, [_('Имя')]),
				E('th', { 'class': 'th' }, [_('IP')]),
				E('th', { 'class': 'th' }, [_('Как подключен')]),
				E('th', { 'class': 'th' }, [_('Сигнал')]),
				E('th', { 'class': 'th' }, [_('MAC')])
			])
		].concat(rows)) : E('p', { 'style': 'color:#57606a;margin:.25rem 0 0' }, [_('Клиентов нет')]);

		var vpnBits = vpn ? E('div', { 'style': 'margin-top:.75rem;color:#24292f' }, [
			_('Туннель: '),
			E('strong', { 'style': 'color:' + (st.tunnel === 'up' ? '#1a7f37' : '#cf222e') },
				[st.tunnel === 'up' ? _('работает') : _('не поднят')]),
			' · ',
			_('handshake '), st.handshake_age_human || '—',
			' · ',
			_('принято '), st.rx_human || '—',
			' · ',
			_('отправлено '), st.tx_human || '—'
		]) : E('div', { 'style': 'margin-top:.75rem;color:#57606a' }, [
			_('Туннель выключен — трафик идёт напрямую через Wi‑Fi.')
		]);

		return E('div', {}, [
			E('h3', { 'style': 'margin:0 0 .35rem' }, [_('Соединения')]),
			E('div', { 'style': 'color:#57606a;font-size:.85rem;margin-bottom:.5rem' }, [
				_('Обновление каждые 5 с')
			]),
			uplinkRow('5 ГГц', st.wwan5_up, st.ssid5, st.sig5, st.ip5, st.gw5),
			uplinkRow('2,4 ГГц', st.wwan24_up, st.ssid24, st.sig24, st.ip24, st.gw24),
			vpnBits,
			E('h3', { 'style': 'margin:1.1rem 0 .35rem' }, [_('Клиенты LAN')]),
			clientBody
		]);
	},

	paint: function(st) {
		var cards = document.getElementById('traffic-cards');
		var stats = document.getElementById('traffic-stats');
		if (cards)
			dom.content(cards, this.renderCards(st));
		if (stats)
			dom.content(stats, this.renderStats(st));
	},

	renderCards: function(st) {
		var wisp = st.mode === 'wisp';
		return [
			this.card('wisp', _('Обычный'),
				_('Весь трафик телефонов и кабеля LAN идёт через чужой Wi‑Fi, без туннеля.'),
				'wisp.svg', wisp),
			this.card('vpn', _('VPN'),
				_('Весь трафик уходит в туннель AmneziaWG. Без туннеля интернета нет.'),
				'vpn.svg', !wisp)
		];
	},

	refresh: function() {
		var self = this;
		if (this._busy)
			return Promise.resolve();
		return fs.exec('/usr/libexec/awg-mode.sh', ['connections']).then(function(res) {
			self.paint(parseConnections(res.stdout || ''));
		}).catch(function() {});
	},

	handlePick: function(mode) {
		var self = this;
		if (this._busy)
			return;
		return fs.exec('/usr/libexec/awg-mode.sh', ['status']).then(function(res) {
			var cur = parseConnections(res.stdout || '').mode || 'vpn';
			if (cur === mode)
				return;
			var title = mode === 'wisp' ? _('Обычный режим') : _('Режим VPN');
			var body = mode === 'wisp'
				? _('Выключить туннель? Интернет пойдёт через чужой Wi‑Fi и кабель LAN.')
				: _('Включить туннель? Весь трафик пойдёт через VPN. Без туннеля интернета не будет.');
			ui.showModal(title, [
				E('p', {}, [body]),
				E('div', { 'class': 'right' }, [
					E('button', {
						'class': 'btn',
						'click': ui.hideModal
					}, [_('Отмена')]),
					' ',
					E('button', {
						'class': 'btn cbi-button-positive important',
						'click': ui.createHandlerFn(self, 'handleApply', mode)
					}, [_('Переключить')])
				])
			]);
		});
	},

	handleApply: function(mode) {
		var self = this;
		var msg = document.getElementById('traffic-msg');
		ui.hideModal();
		this._busy = true;
		dom.content(msg, E('p', {}, [_('Применяю режим… подождите')]));
		var arg = mode === 'wisp' ? 'set-wisp' : 'set-vpn';
		return fs.exec('/usr/libexec/awg-mode.sh', [arg]).then(function(res) {
			var out = (res && res.stdout) || '';
			if (out.indexOf('applied=') >= 0) {
				dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
					mode === 'wisp'
						? _('Обычный режим включён. Uplink подхватывает маршрут несколько секунд.')
						: _('Режим VPN включён. Handshake обычно появляется за 10–30 с.')
				]));
			} else {
				dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [
					_('Не удалось переключить.'), ' ', out || (res && res.stderr) || ''
				]));
			}
			return self.refresh();
		}).catch(function(err) {
			dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		}).finally(function() {
			self._busy = false;
		});
	},

	render: function(st) {
		var self = this;
		if (this._timer) {
			window.clearInterval(this._timer);
			this._timer = null;
		}
		this._timer = window.setInterval(function() {
			self.refresh();
		}, REFRESH_MS);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [_('Режим интернета')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Один режим на Wi‑Fi Travel-VPN и на кабель LAN. Чужую сеть меняют отдельно: '),
				E('a', { 'href': '/cgi-bin/luci/admin/network/wisp' }, [_('Смена Wi‑Fi')]),
				'.'
			]),
			E('div', {
				'id': 'traffic-cards',
				'style': 'display:grid;grid-template-columns:repeat(auto-fit,minmax(16rem,1fr));gap:1rem;margin:1rem 0'
			}, this.renderCards(st)),
			E('div', { 'id': 'traffic-msg' }),
			E('div', {
				'id': 'traffic-stats',
				'class': 'cbi-section',
				'style': 'margin-top:1.25rem;padding:1rem;border:1px solid #d0d7de;border-radius:12px;background:#fff'
			}, [this.renderStats(st)])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
