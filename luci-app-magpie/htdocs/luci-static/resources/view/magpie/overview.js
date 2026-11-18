'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var callStatus = rpc.declare({
	object: 'magpie',
	method: 'status',
	expect: { ok: false, exit_code: 1, output: '' }
});

var callStart = rpc.declare({ object: 'magpie', method: 'start', expect: { ok: false, exit_code: 1, output: '' } });
var callStop = rpc.declare({ object: 'magpie', method: 'stop', expect: { ok: false, exit_code: 1, output: '' } });
var callRestart = rpc.declare({ object: 'magpie', method: 'restart', expect: { ok: false, exit_code: 1, output: '' } });

function notifyResult(title, result) {
	var message = (result && result.output) ? result.output.trim() : '';
	if (!message)
		message = (result && result.ok) ? _('Operation completed.') : _('Operation failed.');
	ui.addNotification(null, E('p', {}, title + ': ' + message), (result && result.ok) ? 'info' : 'danger');
}

function serviceActions() {
	return E('div', { 'class': 'right' }, [
		E('button', {
			'class': 'btn',
			'click': function() {
				return callStart().then(function(result) {
					notifyResult(_('Start'), result);
					window.setTimeout(function() { window.location.reload(); }, 800);
				});
			}
		}, _('Start')),
		' ',
		E('button', {
			'class': 'btn',
			'click': function() {
				return callStop().then(function(result) {
					notifyResult(_('Stop'), result);
					window.setTimeout(function() { window.location.reload(); }, 800);
				});
			}
		}, _('Stop')),
		' ',
		E('button', {
			'class': 'btn cbi-button-action important',
			'click': function() {
				return callRestart().then(function(result) {
					notifyResult(_('Restart'), result);
					window.setTimeout(function() { window.location.reload(); }, 800);
				});
			}
		}, _('Restart'))
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ uci.load('magpie'), callStatus() ]);
	},

	render: function(data) {
		var status = data[1] || {};
		var healthy = !!status.ok;
		var statusText = healthy ? _('Healthy') : (status.output || _('Stopped or degraded'));
		var m = new form.Map('magpie', _('Magpie'),
			_('Manage the OpenWrt service here. Provider and model administration is provided by Magpie Web Console.'));
		var s = m.section(form.NamedSection, 'main', 'magpie', _('Service settings'));
		s.addremove = false;

		var o;
		o = s.option(form.Flag, 'enabled', _('Enable service'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Value, 'gateway_addr', _('Gateway listen address'));
		o.default = '127.0.0.1:3425';
		o.datatype = 'string';
		o.description = _('Default is loopback-only. To allow clients on a trusted LAN/VPN, bind to the router LAN address and restrict access with firewall rules and Gateway API keys. Never expose this port directly to the Internet.');

		o = s.option(form.Value, 'public_url', _('Public gateway URL'));
		o.placeholder = 'https://magpie.example.net';
		o.description = _('Optional MAGPIE_PUBLIC_URL for a TLS reverse-proxy deployment.');

		o = s.option(form.Value, 'data_dir', _('Persistent data directory'));
		o.default = '/etc/magpie';
		o.datatype = 'string';
		o.description = _('Absolute writable path. If using USB/extroot storage, mount it before starting Magpie.');

		return m.render().then(function(mapNode) {
			var statusNode = E('span', {
				'class': healthy ? 'label success' : 'label warning'
			}, statusText);
			var accessInfo = E('div', { 'class': 'alert-message notice' }, [
				E('p', {}, _('The Web Console listens only on 127.0.0.1:3430. LuCI deliberately does not read or transmit its long-term access key. Use an SSH tunnel from your administrator workstation:')),
				E('pre', {}, 'ssh -L 3430:127.0.0.1:3430 root@<router-lan-ip>'),
				E('p', {}, _('In a separate terminal, retrieve the root-only key over SSH:')),
				E('pre', {}, 'ssh root@<router-lan-ip> "cat /etc/magpie/secrets/web.key"'),
				E('p', {}, _('Then open http://127.0.0.1:3430/ in your workstation browser and enter the key in Magpie’s sign-in prompt. Do not share the key or put it in a saved URL.'))
			]);
			var actions = E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Runtime health')),
				E('p', {}, [ _('Service health: '), statusNode ]),
				E('p', {}, status.output || _('No status details available.')),
				serviceActions(),
				E('h3', {}, _('Secure Web Console access')),
				accessInfo
			]);

			return E('div', {}, [ actions, mapNode ]);
		});
	}
});
