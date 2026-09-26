'use strict';
'require view';
'require fs';
'require ui';
'require dom';

var REFRESH_MS = 5000;

function parseKV(text) {
	var st = {};
	String(text || '').split(/\n/).forEach(function(line) {
		var m = line.match(/^([^=]+)=(.*)$/);
		if (m)
			st[m[1]] = m[2];
	});
	return st;
}

function row(label, value, opts) {
	opts = opts || {};
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td', 'style': 'width:11rem;font-weight:600;vertical-align:top' }, [label]),
		E('td', {
			'class': 'td',
			'style': (opts.mono ? 'font-family:ui-monospace,monospace;word-break:break-all;' : '') +
				(opts.color ? ('color:' + opts.color + ';font-weight:600') : '')
		}, [value || '—'])
	]);
}

function onlineLabel(ok, yes, no) {
	return ok ? { text: yes || 'онлайн', color: '#1a7f37' }
		: { text: no || 'нет связи', color: '#cf222e' };
}

return view.extend({
	_timer: null,

	load: function() {
		return fs.exec('/usr/libexec/awg-config.sh', ['stats']).then(function(res) {
			return parseKV(res.stdout || '');
		}).catch(function() {
			return {};
		});
	},

	renderStats: function(st) {
		var tunOk = st.tunnel === 'up';
		var tun = onlineLabel(tunOk, 'работает', 'не поднят');
		var w5 = onlineLabel(st.wwan5_up === '1');
		var w24 = onlineLabel(st.wwan24_up === '1');
		var dump = String(st.awg_dump || '').split('|').join('\n');

		return E('div', {}, [
			E('div', {
				'class': 'cbi-section',
				'style': 'padding:1rem;background:#f6f8fa;border-radius:6px;margin:0 0 1rem'
			}, [
				E('div', { 'style': 'font-size:1.15rem;margin-bottom:.35rem' }, [
					'Туннель: ',
					E('span', { 'style': 'color:' + tun.color + ';font-weight:700' }, [tun.text])
				]),
				E('div', { 'style': 'opacity:.75;font-size:.9em' }, [
					_('Обновлено: ') + (st.updated_at || '—') +
					_(' · автообновление каждые 5 с')
				])
			]),

			E('h3', {}, [_('AmneziaWG')]),
			E('table', { 'class': 'table' }, [
				row(_('Handshake'), st.handshake_age_human || (st.handshake_age ? st.handshake_age + ' с' : '—'),
					{ color: tunOk ? '#1a7f37' : '#cf222e' }),
				row(_('Endpoint'), (st.endpoint_host || '—') + (st.endpoint_port ? (':' + st.endpoint_port) : '')),
				row(_('Адрес туннеля'), st.address),
				row(_('MTU'), st.mtu),
				row(_('Принято'), st.rx_human || st.rx_bytes),
				row(_('Отправлено'), st.tx_human || st.tx_bytes),
				row(_('Keepalive'), st.keepalive ? (st.keepalive + ' с') : '—'),
				row(_('Listen port'), st.listen_port),
				row(_('AllowedIPs'), st.allowed_ips, { mono: true }),
				row(_('Client public key'), st.client_public_key, { mono: true }),
				row(_('Server public key'), st.server_public_key, { mono: true }),
				row(_('Default route'), st.default_route, { mono: true }),
				row(_('Маршрут до endpoint'), st.endpoint_route, { mono: true })
			]),

			E('h3', { 'style': 'margin-top:1.25rem' }, [_('Uplink (WISP)')]),
			E('table', { 'class': 'table' }, [
				row('5 ГГц ' + (st.ssid5 ? '«' + st.ssid5 + '»' : ''), w5.text, { color: w5.color }),
				row('2,4 ГГц ' + (st.ssid24 ? '«' + st.ssid24 + '»' : ''), w24.text, { color: w24.color })
			]),

			E('h3', { 'style': 'margin-top:1.25rem' }, [_('awg show')]),
			E('pre', {
				'style': 'background:#0d1117;color:#e6edf3;padding:1rem;border-radius:6px;overflow:auto;font-size:.85em;white-space:pre-wrap'
			}, [dump || '—'])
		]);
	},

	refresh: function() {
		var self = this;
		var box = document.getElementById('awg-stats-box');
		if (!box)
			return Promise.resolve();
		return fs.exec('/usr/libexec/awg-config.sh', ['stats']).then(function(res) {
			dom.content(box, [self.renderStats(parseKV(res.stdout || ''))]);
		}).catch(function(err) {
			dom.content(box, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
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
			E('h2', {}, [_('Статус VPN')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Живой статус AmneziaWG и uplink. Настройки туннеля — Network → AmneziaWG, смена Wi‑Fi — Смена Wi‑Fi.')
			]),
			E('div', { 'style': 'margin:.75rem 0' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(self, 'refresh')
				}, [_('Обновить сейчас')])
			]),
			E('div', { 'id': 'awg-stats-box' }, [this.renderStats(st || {})])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
