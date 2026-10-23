import { common, Want } from '@kit.AbilityKit';

/**
 * Opens an external http(s)/mailto link with the system browser or handler.
 * Internal Trilium links (#root/...) are routed by TriliumLinkRouter before
 * this service is called.
 */
export class ExternalLinkLauncher {
  static async open(context: common.UIAbilityContext, link: string): Promise<boolean> {
    const target: string = link.trim();
    if (target.length === 0) {
      return false;
    }
    try {
      await context.openLink(target, { appLinkingOnly: false });
      return true;
    } catch (error) {
      // Fall back to an implicit VIEW Want when openLink has no handler.
    }
    try {
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: target
      };
      await context.startAbility(want);
      return true;
    } catch (error) {
      return false;
    }
  }
}
