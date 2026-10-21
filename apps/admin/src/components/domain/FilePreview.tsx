"use client";

import { Download, FileText } from "lucide-react";
import { useEffect, useState } from "react";

import { useI18n } from "@/components/providers/I18nProvider";
import { Button } from "@/components/ui/Button";
import { Dialog } from "@/components/ui/Dialog";
import { ErrorState, Spinner } from "@/components/ui/States";
import { apiBlob } from "@/lib/api/client";

/**
 * Previews a private document/receipt. The file is fetched through the authenticated BFF as a Blob and
 * shown from an object URL; it is never exposed via a public URL. Each view is audited by the API.
 */
export function FilePreviewButton({ path, title, contentType, label }: { path: string; title: string; contentType?: string; label?: string }) {
  const { t } = useI18n();
  const [open, setOpen] = useState(false);
  return (
    <>
      <Button size="sm" variant="secondary" icon={<FileText className="size-4" aria-hidden />} onClick={() => setOpen(true)}>
        {label ?? t.common.preview}
      </Button>
      <Dialog open={open} onClose={() => setOpen(false)} title={title} size="xl">
        {open ? <FileBody path={path} contentType={contentType} title={title} /> : null}
      </Dialog>
    </>
  );
}

function FileBody({ path, contentType, title }: { path: string; contentType?: string; title: string }) {
  const { t } = useI18n();
  const [url, setUrl] = useState<string | null>(null);
  const [type, setType] = useState(contentType ?? "");
  const [error, setError] = useState<unknown>(null);

  useEffect(() => {
    let revoke: string | null = null;
    let cancelled = false;
    apiBlob(path)
      .then((blob) => {
        if (cancelled) return;
        revoke = URL.createObjectURL(blob);
        setType(blob.type || contentType || "");
        setUrl(revoke);
      })
      .catch((err) => !cancelled && setError(err));
    return () => {
      cancelled = true;
      if (revoke) URL.revokeObjectURL(revoke);
    };
  }, [path, contentType]);

  if (error) return <ErrorState error={error} compact />;
  if (!url)
    return (
      <div className="flex h-64 items-center justify-center text-navy-400">
        <Spinner className="size-6" />
      </div>
    );
  return (
    <div className="space-y-3">
      {type.startsWith("image/") ? (
        // eslint-disable-next-line @next/next/no-img-element -- private blob URL, not optimisable
        <img src={url} alt={title} className="mx-auto max-h-[65dvh] rounded-md border border-line object-contain" />
      ) : type === "application/pdf" ? (
        <iframe src={url} title={title} className="h-[65dvh] w-full rounded-md border border-line" />
      ) : (
        <p className="py-10 text-center text-sm text-muted">{t.common.unavailablePreview}</p>
      )}
      <div className="flex justify-end">
        <a href={url} download className="inline-flex items-center gap-1.5 text-sm font-medium text-teal-700 hover:underline">
          <Download className="size-4" aria-hidden />
          {t.common.download}
        </a>
      </div>
    </div>
  );
}
