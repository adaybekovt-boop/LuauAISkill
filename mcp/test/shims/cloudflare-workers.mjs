// Node test stand-in for the workerd-only "cloudflare:workers" module (only the class identity is needed).
export class WorkerEntrypoint {
	constructor(ctx, env) {
		this.ctx = ctx;
		this.env = env;
	}
}
