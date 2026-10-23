import { userAuth } from '@kit.UserAuthenticationKit';

/**
 * Face authentication wrapper. The system owns enrollment and the biometric
 * prompt; the app only asks for a FACE check at application trust level.
 */
export class BiometricService {
  static async authenticate(reason: string): Promise<boolean> {
    return new Promise<boolean>((resolve: (value: boolean) => void) => {
      try {
        const auth: userAuth.UserAuthInstance = userAuth.getUserAuthInstance({
          challenge: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16]),
          authType: [userAuth.UserAuthType.FACE],
          authTrustLevel: userAuth.AuthTrustLevel.ATL1
        }, {
          title: reason
        });
        auth.on('result', {
          onResult: (result: userAuth.UserAuthResult) => {
            resolve(result.result === userAuth.UserAuthResultCode.SUCCESS);
          }
        });
        auth.start();
      } catch (error) {
        resolve(false);
      }
    });
  }
}
