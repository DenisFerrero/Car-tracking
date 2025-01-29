"use strict";

const ApiGateway = require("moleculer-web");
const SocketIOService = require("moleculer-io");

module.exports = {
	name: "api",
	mixins: [ApiGateway, SocketIOService],

	settings: {
		// Exposed port
		port: 4000,

		// Exposed IP
		ip: "0.0.0.0",

		cors: {
			// Configures the Access-Control-Allow-Origin CORS header.
			origin: "*",
		},

		routes: [
			{
				path: "/api",

				whitelist: ["**"],

				mergeParams: true,

				authentication: false,
				authorization: false,

				autoAliases: true,

				bodyParsers: {
					json: {
						strict: false,
						limit: "1MB"
					},
					urlencoded: {
						extended: true,
						limit: "1MB"
					}
				},
				logging: true
			}
		]
	},

	actions: {
		listAliases: { rest: false }
	}
};