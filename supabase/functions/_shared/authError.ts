/** Shared typed HTTP failure; importing it does not construct a backend client. */
export class AuthError extends Error {
  constructor(message:string,public status:number) {
    super(message);
    this.name='AuthError';
  }
}
