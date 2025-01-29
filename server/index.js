const fs = require("fs");
const { ServiceBroker } = require("moleculer");
const config = require("./helpers/config.js");
const migrations = require("./helpers/migration.js");

async function start () {
	const broker = new ServiceBroker({
		logger: true,
		transporter: {
			type: "NATS",
			options: {
				url: config.nats.url,
				token: config.nats.token,
			}
		},
		metadata: config.broker.metadata,
		validator: {
			type: "Fastest",
			options: {
				// Allow to use custom methods for data validation
				useNewCustomCheckerFunction: true,
			}
		},
		/*
			* Understand how configure this params
			* Used just for testing
			*/
		cacher: {
			type: config.cacher.type,
			options: {
				ttl: config.cacher.ttl,
				clone: config.cacher.clone
			}
		}
	});

	migrations();
	
	const services = fs
		.readdirSync("./services")
		.filter(file => file.endsWith(".service.js"));
	
	for (const service of services) {
		broker.createService(require("./services/" + service));
	}
	
	await broker.start();
}

start();