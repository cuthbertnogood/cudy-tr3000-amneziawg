'use strict';
'require view';
'require fs';
'require ui';
'require dom';

var FIELDS = [
	'private_key', 'address', 'dns', 'mtu',
	'endpoint_host', 'endpoint_port', 'server_public_key',
	'allowed_ips', 'keepalive',
	'awg_jc', 'awg_jmin', 'awg_jmax', 'awg_s1', 'awg_s2',
	'awg_h1', 'awg_h2', 'awg_h3', 'awg_h4',
	'client_public_key', 'tunnel', 'handshake_age'
];

function parseKV(text) {
	var st = {};
	FIELDS.forEach(function(k) { st[k] = ''; });
	String(text || '').split(/\n/).forEach(function(line) {
		var m = line.match(/^([^=]+)=(.*)$/);
		if (m)
			st[m[1]] = m[2];
	});
	return st;
}

function val(id) {
	var el = document.getElementById(id);
	return el ? String(el.value || '').trim() : '';
}

function setVal(id, v) {
	var el = document.getElementById(id);
	if (el && v !== undefined && v !== null)
		el.value = v;
}

function fieldRow(id, label, opts) {
	opts = opts || {};
	var input = E('input', {
		'type': opts.type || 'text',
		'id': id,
		'style': 'width:100%;max-width:28rem',
		'autocomplete': 'off',
		'placeholder': opts.placeholder || ''
	});
	if (opts.value)
		input.value = opts.value;
	return E('div', { 'style': 'margin:.55rem 0' }, [
		E('label', { 'for': id, 'style': 'display:block;font-weight:600;margin-bottom:.2rem' }, [label]),
		opts.hint ? E('div', { 'style': 'font-size:.85em;opacity:.75;margin-bottom:.25rem' }, [opts.hint]) : '',
		input
	]);
}

return view.extend({
	load: function() {
		return Promise.all([
			fs.exec('/usr/libexec/awg-config.sh', ['status']).then(function(res) {
				return parseKV(res.stdout || '');
			}).catch(function() { return parseKV(''); }),
			fs.exec('/usr/libexec/awg-config.sh', ['get']).then(function(res) {
				return parseKV(res.stdout || '');
			}).catch(function() { return parseKV(''); })
		]).then(function(pair) {
			return { status: pair[0], cfg: pair[1] };
		});
	},

	renderStatusBox: function(st) {
		var tunOk = st.tunnel === 'up';
		var age = st.handshake_age || '—';
		return E('div', { 'class': 'cbi-section', 'style': 'padding:1rem;background:#f6f8fa;border-radius:6px;margin:1rem 0' }, [
			E('div', {}, [
				'Туннель AmneziaWG: ',
				E('span', { 'style': tunOk ? 'color:#1a7f37;font-weight:600' : 'color:#cf222e;font-weight:600' },
					[tunOk ? 'работает' : 'не поднят'])
			]),
			E('div', {}, ['Endpoint: ', E('strong', {}, [
				(st.endpoint_host || '—') + (st.endpoint_port ? (':' + st.endpoint_port) : '')
			])]),
			E('div', {}, ['Адрес туннеля: ', E('strong', {}, [st.address || '—'])]),
			E('div', {}, ['Handshake age: ', E('strong', {}, [age + (age !== '—' ? ' с' : '')])])
		]);
	},

	refreshStatus: function() {
		var self = this;
		return fs.exec('/usr/libexec/awg-config.sh', ['status']).then(function(res) {
			var st = parseKV(res.stdout || '');
			var el = document.getElementById('awg-status');
			if (el)
				dom.content(el, [self.renderStatusBox(st)]);
		});
	},

	fillForm: function(cfg) {
		[
			'address', 'dns', 'mtu', 'endpoint_host', 'endpoint_port',
			'server_public_key', 'allowed_ips', 'keepalive',
			'awg_jc', 'awg_jmin', 'awg_jmax', 'awg_s1', 'awg_s2',
			'awg_h1', 'awg_h2', 'awg_h3', 'awg_h4'
		].forEach(function(k) {
			if (cfg[k] !== undefined && cfg[k] !== '')
				setVal('awg-' + k, cfg[k]);
		});
		if (cfg.private_key)
			setVal('awg-private_key', cfg.private_key);
		var pub = document.getElementById('awg-client-pub');
		if (pub)
			pub.textContent = cfg.client_public_key || '—';
	},

	handleUpload: function(ev) {
		var file = (ev.target.files || [])[0];
		var msg = document.getElementById('awg-msg');
		var self = this;
		if (!file)
			return;

		dom.content(msg, E('p', {}, [_('Читаю файл…')]));

		return new Promise(function(resolve, reject) {
			var reader = new FileReader();
			reader.onload = function() { resolve(reader.result); };
			reader.onerror = function() { reject(reader.error || new Error('read failed')); };
			reader.readAsText(file);
		}).then(function(text) {
			return fs.write('/tmp/awg-upload.conf', String(text)).then(function() {
				return fs.exec('/usr/libexec/awg-config.sh', ['parse', '/tmp/awg-upload.conf']);
			});
		}).then(function(res) {
			var cfg = parseKV((res && res.stdout) || '');
			if (!cfg.endpoint_host && !cfg.server_public_key) {
				dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [
					_('Не похоже на AmneziaWG/WireGuard .conf (нет Endpoint / PublicKey).')
				]));
				return;
			}
			self.fillForm(cfg);
			dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
				_('Файл загружен в форму. Проверьте поля и нажмите «Применить».')
			]));
		}).catch(function(err) {
			dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		});
	},

	handleApply: function() {
		var msg = document.getElementById('awg-msg');
		var self = this;
		var lines = [
			'private_key=' + val('awg-private_key'),
			'address=' + val('awg-address'),
			'dns=' + val('awg-dns'),
			'mtu=' + val('awg-mtu'),
			'endpoint_host=' + val('awg-endpoint_host'),
			'endpoint_port=' + val('awg-endpoint_port'),
			'server_public_key=' + val('awg-server_public_key'),
			'allowed_ips=' + val('awg-allowed_ips'),
			'keepalive=' + val('awg-keepalive'),
			'awg_jc=' + val('awg-awg_jc'),
			'awg_jmin=' + val('awg-awg_jmin'),
			'awg_jmax=' + val('awg-awg_jmax'),
			'awg_s1=' + val('awg-awg_s1'),
			'awg_s2=' + val('awg-awg_s2'),
			'awg_h1=' + val('awg-awg_h1'),
			'awg_h2=' + val('awg-awg_h2'),
			'awg_h3=' + val('awg-awg_h3'),
			'awg_h4=' + val('awg-awg_h4')
		].join('\n') + '\n';

		if (!val('awg-endpoint_host') || !val('awg-server_public_key') || !val('awg-address')) {
			ui.addNotification(null, E('p', {}, [
				_('Нужны как минимум: адрес туннеля, endpoint и public key сервера')
			]), 'warning');
			return;
		}

		dom.content(msg, E('p', {}, [_('Применяю… сеть перезагрузится на несколько секунд')]));

		return fs.write('/tmp/awg-apply.kv', lines).then(function() {
			return fs.exec('/bin/sh', ['-c',
				'/usr/libexec/awg-config.sh apply < /tmp/awg-apply.kv; rm -f /tmp/awg-apply.kv /tmp/awg-upload.conf']);
		}).then(function(res) {
			var out = (res && res.stdout) || '';
			var err = (res && res.stderr) || '';
			if (out.indexOf('applied=1') >= 0) {
				dom.content(msg, E('p', { 'style': 'color:#1a7f37' }, [
					_('Сохранено. Обновите статус через 15–30 с (handshake).')
				]));
				setVal('awg-private_key', '');
			} else {
				dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [
					_('Не удалось применить.'), ' ', out || err
				]));
			}
			return self.refreshStatus();
		}).catch(function(err) {
			dom.content(msg, E('p', { 'style': 'color:#cf222e' }, [String(err)]));
		});
	},

	render: function(data) {
		var st = data.status || {};
		var cfg = data.cfg || {};
		var self = this;

		var form = E('div', { 'id': 'awg-form', 'class': 'cbi-section', 'style': 'margin:1rem 0' }, [
			E('h3', {}, [_('Загрузить .conf')]),
			E('p', {}, [_('Файл из AmneziaVPN / WireGuard с секциями [Interface] и [Peer]. Параметры Jc/Jmin/… подставятся, если есть в файле.')]),
			E('input', {
				'type': 'file',
				'accept': '.conf,.txt,text/plain',
				'change': ui.createHandlerFn(self, 'handleUpload')
			}),

			E('h3', { 'style': 'margin-top:1.5rem' }, [_('Или вручную')]),
			E('p', {}, [
				_('Client public key (для сервера): '),
				E('code', { 'id': 'awg-client-pub' }, [cfg.client_public_key || '—'])
			]),
			fieldRow('awg-private_key', _('Private key клиента'), {
				type: 'password',
				hint: _('Оставьте пустым, чтобы не менять текущий ключ'),
				placeholder: '••••••••'
			}),
			fieldRow('awg-address', _('Address'), { value: cfg.address || '10.9.0.3/24' }),
			fieldRow('awg-endpoint_host', _('Endpoint (IP или хост)'), { value: cfg.endpoint_host || '' }),
			fieldRow('awg-endpoint_port', _('Порт'), { value: cfg.endpoint_port || '443' }),
			fieldRow('awg-server_public_key', _('Public key сервера'), { value: cfg.server_public_key || '' }),
			fieldRow('awg-allowed_ips', _('AllowedIPs'), { value: cfg.allowed_ips || '0.0.0.0/0' }),
			fieldRow('awg-keepalive', _('PersistentKeepalive'), { value: cfg.keepalive || '25' }),
			fieldRow('awg-mtu', _('MTU'), { value: cfg.mtu || '1280' }),
			fieldRow('awg-dns', _('DNS'), { value: cfg.dns || '1.1.1.1' }),

			E('h4', { 'style': 'margin-top:1.25rem' }, [_('Маскировка AmneziaWG')]),
			E('p', { 'style': 'font-size:.9em;opacity:.8' }, [
				_('Должны совпадать с сервером. Иначе handshake не поднимется.')
			]),
			fieldRow('awg-awg_jc', 'Jc', { value: cfg.awg_jc || '4' }),
			fieldRow('awg-awg_jmin', 'Jmin', { value: cfg.awg_jmin || '40' }),
			fieldRow('awg-awg_jmax', 'Jmax', { value: cfg.awg_jmax || '70' }),
			fieldRow('awg-awg_s1', 'S1', { value: cfg.awg_s1 || '0' }),
			fieldRow('awg-awg_s2', 'S2', { value: cfg.awg_s2 || '0' }),
			fieldRow('awg-awg_h1', 'H1', { value: cfg.awg_h1 || '1' }),
			fieldRow('awg-awg_h2', 'H2', { value: cfg.awg_h2 || '2' }),
			fieldRow('awg-awg_h3', 'H3', { value: cfg.awg_h3 || '3' }),
			fieldRow('awg-awg_h4', 'H4', { value: cfg.awg_h4 || '4' }),

			E('div', { 'style': 'margin:1.25rem 0;display:flex;gap:.75rem;flex-wrap:wrap' }, [
				E('button', {
					'class': 'btn cbi-button cbi-button-save',
					'click': ui.createHandlerFn(self, 'handleApply')
				}, [_('Применить')]),
				E('button', {
					'class': 'btn cbi-button cbi-button-action',
					'click': ui.createHandlerFn(self, 'refreshStatus')
				}, [_('Обновить статус')])
			])
		]);

		/* заполнить после вставки в DOM — значения уже в fieldRow value */
		window.setTimeout(function() {
			self.fillForm(cfg);
		}, 0);

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, [_('AmneziaWG')]),
			E('div', { 'class': 'cbi-map-descr' }, [
				_('Настройка туннеля до VPS. Смена чужого Wi‑Fi — отдельно: Network → Смена Wi‑Fi.')
			]),
			E('div', { 'id': 'awg-status' }, [this.renderStatusBox(st)]),
			E('div', { 'id': 'awg-msg' }),
			form
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
