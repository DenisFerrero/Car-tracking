const _ = require("lodash");
const { version: VERSION } = require("../package.json");

let config = null;

module.exports = function () {
	if (!config) {
		config = { };
		/**
		 * Read environment variables and assign them to the config object
		 * 
		 * 1. Variable name
		 * 2. Path and key in the config object
		 * 3. Type of the variable
		 * 4. Default value if any
		 */
		
		const variables = [
			["VERSION", "broker.metadata.version", "string", VERSION],
			["DEBUG", "debug", "boolean", false],
			["MQTT_URL", "mqtt.url", "string", "mqtt://admin:admin@localhost:1883"],
			// Sequelize connection config
			["DB_DIALECT", "sequelize.dialect", "string", "postgres"],
			["DB_HOST", "sequelize.host", "string", "localhost"],
			["DB_PORT", "sequelize.port", "string", "5432"],
			["DB_QUERY_TIMEOUT", "sequelize.queryExecutionTimeout", "number", 0],
			["DB_PARANOID", "sequelize.paranoid", "boolean", false],
			["DB_TIMESTAMPS", "sequelize.timestamps", "boolean", false],
			["DB_UNDERSCORED", "sequelize.define.underscored", "boolean", true],
			["DB_LOGGING", "sequelize.logging", "boolean", false],
			// Postgres connection config override
			["POSTGRES_DB", "sequelize.database", "string", "car_tracking"],
			["POSTGRES_USER", "sequelize.user", "string", "postgres"],
			["POSTGRES_PASSWORD", "sequelize.password", "string", "CarTracking12345!!"],
			["TZ", "timezone", "string", "Europe/Rome"],
			["CACHER_TYPE", "cacher.type", "string", "memory"],
			["CACHER_TTL", "cacher.ttl", "number", 10 * 60],
			["CACHER_CLONE", "cacher.clone", "boolean", true],
		];
		
		for (const variable of variables) {
			const [env, configKey, type = "string", defaultValue = undefined] = variable;
			let value = process.env[env];
			// Apply default value if any
			if (value === undefined && defaultValue !== undefined)
				value = defaultValue;
			// If the value is undefined and a value is already stored  skip further steps
			if (value === undefined && _.get(config, configKey, undefined) !== undefined) {
				continue;
			}
			// Set the value as undefined
			else if (value === undefined) {
				_.set(config, configKey, undefined);
			}
			// Otherwise parse the value and set it
			else {
				switch (type) {
					case "number":
						value = Number(value);
						break;
					case "boolean":
						value = value === "true" || value === true;
						break;
					case "string":
					default:
						break;
				}
				_.set(config, configKey, value);
			}
		}
	}

	return config;
};
