module.exports = {
	async up ({ context: queryInterface }) {
		const transaction = await queryInterface.sequelize.transaction();
		try {
			await queryInterface.sequelize.query("SELECT add_retention_policy('coordinates', INTERVAL '2 months');", { transaction });
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
			await queryInterface.sequelize.query("SELECT remove_retention_policy('coordinates');", { transaction });
			// Commit the transaction
			await transaction.commit();
		} catch (err) {
			await transaction.rollback();
			throw err;
		}
	}
};