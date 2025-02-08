const Sequelize = require("sequelize");
const config = (require("./config"))();

let sequelize = null;

if (!sequelize) {
	sequelize = new Sequelize(config.sequelize.database, config.sequelize.user, config.sequelize.password, config.sequelize);
}

module.exports = sequelize;