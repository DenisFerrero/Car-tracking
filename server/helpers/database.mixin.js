const DbService = require("moleculer-db");
const SqlAdapterSequelize = require("moleculer-db-adapter-sequelize");

module.exports = function (name, model, options = {}) {
	const sequelize = require("../helpers/sequelize.js");
	const iModel = sequelize.define(name, model, options);

	let adapter = new SqlAdapterSequelize(sequelize);

	return {
		mixins: [DbService],
		adapter,
		model: iModel,

		settings: {
			idField: "id",
			defaultSort: "name",
		},

		actions: {
			count: {
				rest: "GET /count",
			}
		},
	};
};