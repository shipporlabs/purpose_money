// Verify Firebase Auth ID tokens sent by the Flutter app.
import { createRemoteJWKSet, jwtVerify } from 'jose';

const JWKS = createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));

export interface AuthUser { uid: string; email?: string; name?: string }

export async function verifyIdToken(token: string, projectId: string): Promise<AuthUser> {
  const { payload } = await jwtVerify(token, JWKS, {
    issuer: `https://securetoken.google.com/${projectId}`,
    audience: projectId,
    algorithms: ['RS256'],
  });
  if (!payload.sub) throw new Error('Token has no subject');
  return { uid: payload.sub, email: payload.email as string | undefined, name: payload.name as string | undefined };
}
