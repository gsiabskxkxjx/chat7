// إعدادات خادم TURN من metered.ca (Credentials ← Get credential ← Show ICE Servers Array).
// ضروري لمكالمات بين شبكات مختلفة (بيانات وواي فاي) ومع الـ VPN.
const turnUrls = <String>[
  'turn:global.relay.metered.ca:80',
  'turn:global.relay.metered.ca:80?transport=tcp',
  'turn:global.relay.metered.ca:443',
  'turns:global.relay.metered.ca:443?transport=tcp',
];
const turnUsername = '92b7fc3a896973e8874be348';
const turnCredential = 'v5e7RCx4T33yEoR8';
