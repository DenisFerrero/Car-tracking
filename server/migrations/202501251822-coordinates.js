const { Sequelize } = require("sequelize");

module.exports = {
	async up ({ context: queryInterface }) {
		const transaction = await queryInterface.sequelize.transaction();
		try {
			await queryInterface.createTable("coordinates", {
				timestamp: { type: Sequelize.DATE, allowNull: false, primaryKey: true },
				x: { type: Sequelize.REAL, allowNull: false },
				y: { type: Sequelize.REAL, allowNull: false },
				altitude: { type: Sequelize.REAL, allowNull: true },
				pressure: { type: Sequelize.REAL, allowNull: true },
				temperature: { type: Sequelize.REAL, allowNull: true },
				device_id: { type: Sequelize.INTEGER, allowNull: false }
			}, { transaction });

			await queryInterface.sequelize.query("SELECT create_hypertable('coordinates', 'timestamp');", { transaction });
			// Commit the transaction
			await transaction.commit();
		} catch (err) {
			await transaction.rollback();
			throw err;
		}
	},
	async down ({ context: queryInterface }) {
		const transaction = await queryInterface.sequelize.transaction();
		try {
			await queryInterface.dropTable("coordinates", { transaction });
			// Commit the transaction
			await transaction.commit();
		} catch (err) {
			await transaction.rollback();
			throw err;
		}
	}
};