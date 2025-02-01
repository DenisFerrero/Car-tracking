const database = require("../helpers/database.mixin");
const sequelize = require("sequelize");
const { DataTypes } = sequelize;

const model = {
	id: { type: DataTypes.INTEGER, allowNull: false, primaryKey: true },
	name: { type: DataTypes.STRING, allowNull: false },
	part_number: { type: DataTypes.STRING, allowNull: false },
	serial_number: { type: DataTypes.STRING, allowNull: false },
	manufacturer: { type: DataTypes.STRING, allowNull: true },
	model: { type: DataTypes.STRING, allowNull: true },
	revision: { type: DataTypes.STRING, allowNull: true },
	imei: { type: DataTypes.STRING, allowNull: true }
};

module.exports = {
	name: "devices",

	mixins: [database("devices", model, { paranoid: true, timestamps: true })],

	settings: {
		rest: "devices"
	},

	hooks: {
		after: {
			async update (ctx, res) {
				await ctx.call("api.broadcast", {
					event:"devices.changed",
					args: [res],
					volatile: true,
				});

				return res;
			}
		}
	},

	actions: {
		create: { rest: false },
		remove: { rest: false },
		insert: { rest: false },

		discover: {
			params: {
				part_number: { type: "string" },
				serial_number: { type: "string" },
				imei: { type: "string" },
				manufacturer: { type: "string", optional: true },
				model: { type: "string", optional: true },
				revision: { type: "string", optional: true },
			},
			async handler (ctx) {
				const where = { imei: ctx.params.imei };

				const found = await this._find(ctx, { query: where });
				let result = null;

				// Item already exists, return the id
				if (Array.isArray(found) && found.length > 0) {
					result = found[0].id;
				// Create new record
				} else {
					const params = this.sanitizeParams(ctx, this.params);
					params.name = ctx.params.imei;
					const created = this._create(ctx, params);
					result = created.id;

					await ctx.call("api.broadcast", {
						event:"devices.changed",
						args: [result],
						volatile: true,
					});
				}

				await ctx.broadcast("devices.discover." + ctx.params.imei, { id: result });
				return true;
			}
		}
	}
};