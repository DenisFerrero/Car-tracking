const database = require("../helpers/database.mixin");
const sequelize = require("sequelize");
const { DataTypes } = sequelize;

const model = {
	timestamp: { type: DataTypes.DATE, allowNull: false, primaryKey: true },
	x: { type: DataTypes.REAL, allowNull: false },
	y: { type: DataTypes.REAL, allowNull: false },
	altitude: { type: DataTypes.REAL, allowNull: true },
	pressure: { type: DataTypes.REAL, allowNull: true },
	temperature: { type: DataTypes.REAL, allowNull: true },
	device_id: { type: DataTypes.INTEGER, allowNull: false }
};

module.exports = {
	name: "coordinates",

	mixins: [database("coordinates", model, { paranoid: false, timestamps: false })],

	settings: {
		rest: "coordinates"
	},

	actions: {
		create: { rest: false },
		update: { rest: false },
		remove: { rest: false },
		insert: { rest: false },

		store: {
			params: {
				x: { type: "number" },
				y: { type: "number" },
				altitude: { type: "number", optional: true },
				pressure: { type: "number", optional: true },
				temperature: { type: "number", optional: true },
				device_id: { type: "number" }
			},
			async handler (ctx) {
				// Find the device, if not found throw error
				await ctx.call("devices.get", { id: ctx.params.device_id });
				// Create the record with the results
				const params = this.sanitizeParams(ctx, ctx.params);
				params.timestamp = new Date().toISOString();
				const res = await this._create(ctx, params);

				ctx.call("io.broadcast", {
					event:"coordinates.device." + res.device_id,
					args: [res],
					volatile: true,
				});

				return true;
			}
		}
	},

	// TODO Remove it
	// async started () {
	// 	let last = (await this._find(this.broker, { query: { device_id: 1 }, sort: "-timestamp" }))[0];

	// 	const emitCoordinates = () => {
	// 		last.x += 0.0008;
	// 		last.y += 0.0008;
	// 		last.altitude += Math.random() * 6 - 3;
	// 		last.pressure += Math.random() * 6 - 3;
	// 		last.temperature += Math.random() * 6 - 3;
	// 		last.timestamp = new Date();

	// 		this.broker.call("api.broadcast", {
	// 			event:"coordinates.device." + last.device_id,
	// 			args: [last],
	// 			volatile: true,
	// 		});

	// 		setTimeout(emitCoordinates, 2000);
	// 	};

	// 	emitCoordinates();
	// }
};