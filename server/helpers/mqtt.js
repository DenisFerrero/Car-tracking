const mqtt = require("mqtt");
const config = (require("./config"))();

let client = null;

module.exports = function () {
	if (!client) {
		client = mqtt.connect(config.mqtt.url);
	}

	return client;
};