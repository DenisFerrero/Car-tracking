const { Sequelize } = require("sequelize");

module.exports = {
	async up ({ context: queryInterface }) {
		const transaction = await queryInterface.sequelize.transaction();
		try {
			await queryInterface.createTable("devices", {
				id: { type: Sequelize.INTEGER, allowNull: false, primaryKey: true },
				name: { type: Sequelize.STRING, allowNull: false },
				part_number: { type: Sequelize.STRING, allowNull: false },
				serial_number: { type: Sequelize.STRING, allowNull: false },
				imei: { type: Sequelize.STRING, allowNull: false },
				manufacturer: { type: Sequelize.STRING, allowNull: true },
				model: { type: Sequelize.STRING, allowNull: true },
				revision: { type: Sequelize.STRING, allowNull: true },
				created_at: { type: Sequelize.DATE, allowNull: false },
				updated_at: { type: Sequelize.DATE, allowNull: false },
				deleted_at: { type: Sequelize.DATE, allowNull: true },
			}, { transaction });
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
			await queryInterface.dropTable("devices", { transaction });
			// Commit the transaction
			await transaction.commit();
		} catch (err) {
			await transaction.rollback();
			throw err;
		}
	}
};