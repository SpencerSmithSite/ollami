from fastapi import APIRouter, HTTPException, UploadFile
from fastapi.responses import FileResponse

from utils.storage import content_type_for, delete_file, get_file_path, list_file_ids, save_file

router = APIRouter(prefix="/v1/files", tags=["files"])


@router.get("", response_model=list[str])
def list_files():
    return list_file_ids()


@router.post("", status_code=201)
async def upload_file(file: UploadFile):
    filename = file.filename or "upload.bin"
    data = await file.read()
    file_id = save_file(data, filename)
    del data
    return {"file_id": file_id}


@router.get("/{file_id}")
def download_file(file_id: str):
    path = get_file_path(file_id)
    if path is None:
        raise HTTPException(status_code=404, detail="file not found")
    return FileResponse(path=str(path), media_type=content_type_for(file_id), filename=file_id)


@router.delete("/{file_id}", status_code=204)
def remove_file(file_id: str):
    if not delete_file(file_id):
        raise HTTPException(status_code=404, detail="file not found")
