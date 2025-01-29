/**
 * Support for database migrations and seeders
 * 
 * @module helpers/migration
 */
const path = require("path");
const { Umzug, SequelizeStorage } = require("umzug");
const sequelize = require("./sequelize");

/**
 * Run pending migrations
 * 
 * @async
 */
module.exports = async function () {
	// UMZUG Migration
	const uProject = new Umzug({
		migrations: {
			glob: path.join("migrations","*.js").replace(/\\/g,"/")
		},
		logger: null,
		context: sequelize.getQueryInterface(),
		storage: new SequelizeStorage({
			sequelize,
			modelName: ".migrations",
			tableName: ".migrations"
		})
	});

	await uProject.up();
};